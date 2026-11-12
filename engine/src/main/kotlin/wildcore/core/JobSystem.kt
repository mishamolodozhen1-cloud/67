package wildcore.core

import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.PriorityBlockingQueue
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Worker pool with a priority queue (lower value runs first) plus a main-thread completion queue.
 * Chunk generation/meshing run here; GPU uploads are marshalled back with [runOnMain].
 */
class JobSystem(threadCount: Int) {
    private class Job(val priority: Float, val seq: Long, val task: Runnable) : Comparable<Job> {
        override fun compareTo(other: Job): Int {
            val c = priority.compareTo(other.priority)
            return if (c != 0) c else seq.compareTo(other.seq)
        }
    }

    private val queue = PriorityBlockingQueue<Job>()
    private val mainQueue = ConcurrentLinkedQueue<Runnable>()
    private val seq = AtomicLong()
    private val active = AtomicInteger()
    @Volatile private var running = true
    private val threads: List<Thread>
    val workerCount: Int = threadCount

    init {
        threads = List(threadCount) { idx ->
            Thread({
                while (running) {
                    val job = try { queue.take() } catch (e: InterruptedException) { break }
                    active.incrementAndGet()
                    try { job.task.run() } catch (t: Throwable) { Log.e("JobSystem", "job failed", t) }
                    finally { active.decrementAndGet() }
                }
            }, "wildcore-worker-$idx").apply {
                isDaemon = true
                priority = Thread.NORM_PRIORITY - 1
                start()
            }
        }
    }

    fun submit(priority: Float, task: Runnable) { queue.add(Job(priority, seq.getAndIncrement(), task)) }
    fun runOnMain(task: Runnable) { mainQueue.add(task) }

    /** Runs queued main-thread callbacks; stops early once [budgetNanos] is spent (never starves: runs at least one). */
    fun drainMain(budgetNanos: Long) {
        val start = System.nanoTime()
        while (true) {
            val r = mainQueue.poll() ?: return
            try { r.run() } catch (t: Throwable) { Log.e("JobSystem", "main task failed", t) }
            if (System.nanoTime() - start > budgetNanos) return
        }
    }

    val pending: Int get() = queue.size + active.get()
    val pendingMain: Int get() = mainQueue.size

    fun shutdown() {
        running = false
        queue.clear()
        for (t in threads) t.interrupt()
    }
}
