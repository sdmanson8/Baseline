# ThreadPool callbacks must be CLR delegates, not PowerShell scriptblocks:
# pool threads do not have a PowerShell runspace and cannot invoke scriptblocks.
if (-not ('Baseline.GuiExecution.WorkerLifecycle' -as [type]))
{
    Add-Type -ReferencedAssemblies ([System.Management.Automation.PowerShell].Assembly.Location) -TypeDefinition @'
#define TRACE
using System;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.IO;

namespace Baseline.GuiExecution
{
    public static class WorkerLifecycle
    {
        private static void CleanupStep(Action action, string operation)
        {
            try { action(); }
            catch (PipelineStoppedException) { }
            catch (Exception error)
            {
                Trace.TraceWarning("GUI worker {0}: {1}", operation, error);
            }
        }

        public static void RequestStop(PowerShell worker)
        {
            if (worker == null) return;
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                CleanupStep(worker.Stop, "stop");
            });
        }

        public static void StopAndDispose(PowerShell worker, IAsyncResult invocation, Runspace runspace)
        {
            StopAndDispose(worker, invocation, runspace, null);
        }

        public static void StopAndDispose(PowerShell worker, IAsyncResult invocation, Runspace runspace, string ownedTemporaryFile)
        {
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                if (worker != null)
                {
                    CleanupStep(worker.Stop, "stop");
                    if (invocation != null)
                        CleanupStep(delegate { worker.EndInvoke(invocation); }, "finalize");
                    CleanupStep(worker.Dispose, "dispose");
                }
                if (runspace != null)
                {
                    CleanupStep(runspace.Close, "close runspace");
                    CleanupStep(runspace.Dispose, "dispose runspace");
                }
                if (!String.IsNullOrEmpty(ownedTemporaryFile))
                    CleanupStep(delegate { File.Delete(ownedTemporaryFile); }, "remove worker temporary file");
            });
        }

        public static void StopPoolAndDispose(PowerShell[] workers, RunspacePool pool, IAsyncResult opening)
        {
            // All stop requests run independently: one blocked provider must not
            // prevent cancellation of the other pipelines in the pool.
            foreach (PowerShell worker in workers) RequestStop(worker);
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                // Finish asynchronous initialization before closing the pool;
                // otherwise an opening runspace can outlive the closed pool.
                if (pool != null && opening != null)
                    CleanupStep(delegate { pool.EndOpen(opening); }, "finish opening pool");
                foreach (PowerShell worker in workers)
                    CleanupStep(worker.Dispose, "dispose pooled worker");
                if (pool != null)
                {
                    CleanupStep(pool.Close, "close pool");
                    CleanupStep(pool.Dispose, "dispose pool");
                }
            });
        }
    }
}
'@
}
