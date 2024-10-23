# art gc相关死锁黑屏问题总结


### 背景：

从测试同学那边拿过来两台黑屏的机器，点击电源、屏幕都没有反应，不过还好adb可以链接，有root权限，一番deubgging后，确认表面原因是system_server进程的art虚拟机卡在了gc前flip线程状态的操作中，而最终的root cause也比较有意思，所以本文就简单记录下问题的排查过程。

<!-- more -->

#### 1. 按照习惯，快速检查下是否发生了watchdog
```
$ adb shell ``ls` `-l ``/data/anr/
-rw------- 1 system system 53592 2019-05-03 14:21 anr_2019-05-03-14-21-53-368
-rw------- 1 system system 845398 2019-05-03 14:30 anr_2019-05-03-14-30-03-498
-rw------- 1 system system 1078028 2019-05-03 14:58 anr_2019-05-03-14-58-40-505
-rw------- 1 system system 1060669 2019-05-03 14:59 anr_2019-05-03-14-59-00-410
-rw------- 1 system system 527393 2019-05-03 17:32 anr_2019-05-03-17-32-22-852
-rw------- 1 system system 619826 2019-05-03 17:33 anr_2019-05-03-17-32-58-212
// ...
```
并没有watchdog相关日志

#### 2.  查看系统当前时间
```
`$ adb shell ``date``Sun May  5 13:52:25 CST 2019`
```

#### 3. 查看system_server进程各个线程的状态

```
$ pid=`adb shell pidof system_server` && adb shell ``ps` `-T $pid
USER           PID   TID  PPID     VSZ    RSS WCHAN            ADDR S CMD           
system        1471  1471   635 11629888 168336 futex_wait_queue_me 0 S system_server
system        1471  1477   635 11629888 168336 do_sigtimedwait    0 S Signal Catcher
system        1471  1478   635 11629888 168336 futex_wait_queue_me 0 S ADB-JDWP Connec
system        1471  1479   635 11629888 168336 futex_wait_queue_me 0 S Binder:filter-p
system        1471  1480   635 11629888 168336 poll_schedule_timeout 0 S Binder:``read``-per
system        1471  1481   635 11629888 168336 futex_wait_queue_me 0 S ReferenceQueueD
system        1471  1482   635 11629888 168336 futex_wait_queue_me 0 S FinalizerDaemon
system        1471  1483   635 11629888 168336 futex_wait_queue_me 0 S FinalizerWatchd
system        1471  1484   635 11629888 168336 futex_wait_queue_me 0 S HeapTaskDaemon
system        1471  1524   635 11629888 168336 futex_wait_queue_me 0 S Binder:1471_1
system        1471  1525   635 11629888 168336 futex_wait_queue_me 0 S Binder:1471_2
system        1471  1673   635 11629888 168336 futex_wait_queue_me 0 S android.``bg
system        1471  1675   635 11629888 168336 futex_wait_queue_me 0 S ActivityManager
system        1471  1676   635 11629888 168336 SyS_epoll_wait     0 S android.ui
system        1471  1677   635 11629888 168336 SyS_epoll_wait     0 S ActivityManager
system        1471  1678   635 11629888 168336 SyS_epoll_wait     0 S ActivityManager
system        1471  1684   635 11629888 168336 futex_wait_queue_me 0 S batterystats-wo
system        1471  1687   635 11629888 168336 wait_woken         0 S FileObserver
system        1471  1688   635 11629888 168336 futex_wait_queue_me 0 S android.``fg
system        1471  1689   635 11629888 168336 futex_wait_queue_me 0 S android.io
system        1471  1690   635 11629888 168336 futex_wait_queue_me 0 S android.display
system        1471  1691   635 11629888 168336 futex_wait_queue_me 0 S CpuTracker
system        1471  1692   635 11629888 168336 futex_wait_queue_me 0 S PowerManagerSer
system        1471  1693   635 11629888 168336 futex_wait_queue_me 0 S BatteryStats_wa
system        1471  1694   635 11629888 168336 SyS_epoll_wait     0 S work-thread
system        1471  1695   635 11629888 168336 SyS_epoll_wait     0 S PackageManager
system        1471  1696   635 11629888 168336 SyS_epoll_wait     0 S PackageManager
system        1471  1817   635 11629888 168336 SyS_epoll_wait     0 S PackageInstalle
system        1471  1821   635 11629888 168336 SyS_epoll_wait     0 S android.anim
system        1471  1822   635 11629888 168336 SyS_epoll_wait     0 S android.anim.lf
...
```
这一步主要是快速检查下有没有D（disk blocked）状态的线程

#### 3. 查看system_server进程backtrace

```
$ pid=`adb shell pidof system_server` && adb shell ``kill` `-3 $pid
```

得到：
<details>
<summary>点击展开完整backtrace!</summary>

```java
----- pid 1471 at 2019-05-05 11:07:04 -----
Cmd line: system_server
Build fingerprint: 'Xiaomi/ursa/ursa:9/PKQ1.180729.001/9.4.25:user/release-keys'
ABI: 'arm64'
Build type: optimized
Zygote loaded classes=8981 post zygote classes=4480
Intern table: 91336 strong; 9128 weak
JNI: CheckJNI is off; globals=35793 (plus 15391 weak)
Libraries: /system/lib64/libandroid.so /system/lib64/libandroid_servers.so /system/lib64/libcompiler_rt.so /system/lib64/libjavacrypto.so /system/lib64/libjnigraphics.so /system/lib64/libmedia_jni.so /system/lib64/libmiui_security.so /system/lib64/libmiuiclassproxy.so /system/lib64/libmiuinative.so /system/lib64/libqti_performance.so /system/lib64/libshell_jni.so /system/lib64/libsoundpool.so /system/lib64/libthemeutils_jni.so /system/lib64/libwebviewchromium_loader.so /system/lib64/libwifi-service.so libjavacore.so libopenjdk.so (17)
/system/priv-app/Telecom/oat/arm64/Telecom.odex: speed
/system/priv-app/SettingsProvider/oat/arm64/SettingsProvider.odex: speed
/system/framework/oat/arm64/ethernet-service.odex: speed
/system/framework/oat/arm64/services.odex: speed
/system/framework/oat/arm64/com.android.location.provider.odex: speed
/system/framework/oat/arm64/wifi-service.odex: speed
Running non JIT
Number of block bounds check elimination deoptimizations: 1

suspend all histogram:	Sum: 38.363s 99% C.I. 20.839us-10074.349us Avg: 413.165us Max: 180322us
DALVIK THREADS (182):
"Signal Catcher" daemon prio=5 tid=2 Runnable
  | group="system" sCount=0 dsCount=0 flags=0 obj=0x13fc2a78 self=0x7232a0e000
  | sysTid=1477 nice=0 cgrp=default sched=0/0 handle=0x72329ff4f0
  | state=R schedstat=( 53450056593 38039194029 71940 ) utm=2993 stm=2352 core=5 HZ=100
  | stack=0x7232904000-0x7232906000 stackSize=1009KB
  | held mutexes= "mutator lock"(shared held)
  native: #00 pc 00000000003c3bf4  /system/lib64/libart.so (art::DumpNativeStack(std::__1::basic_ostream<char, std::__1::char_traits<char>>&, int, BacktraceMap*, char const*, art::ArtMethod*, void*, bool)+220)
  native: #01 pc 0000000000494e60  /system/lib64/libart.so (art::Thread::DumpStack(std::__1::basic_ostream<char, std::__1::char_traits<char>>&, bool, BacktraceMap*, bool) const+352)
  native: #02 pc 00000000004b03ac  /system/lib64/libart.so (art::DumpCheckpoint::Run(art::Thread*)+936)
  native: #03 pc 00000000004a925c  /system/lib64/libart.so (art::ThreadList::RunCheckpoint(art::Closure*, art::Closure*, bool)+856)
  native: #04 pc 00000000004a7fa0  /system/lib64/libart.so (art::ThreadList::Dump(std::__1::basic_ostream<char, std::__1::char_traits<char>>&, bool)+1068)
  native: #05 pc 00000000004a7aa0  /system/lib64/libart.so (art::ThreadList::DumpForSigQuit(std::__1::basic_ostream<char, std::__1::char_traits<char>>&)+884)
  native: #06 pc 0000000000476890  /system/lib64/libart.so (art::Runtime::DumpForSigQuit(std::__1::basic_ostream<char, std::__1::char_traits<char>>&)+176)
  native: #07 pc 0000000000482758  /system/lib64/libart.so (art::SignalCatcher::HandleSigQuit()+1372)
  native: #08 pc 0000000000481430  /system/lib64/libart.so (art::SignalCatcher::Run(void*)+256)
  native: #09 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #10 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"main" prio=5 tid=1 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x78e03410 self=0x7239614c00
  | sysTid=1471 nice=-2 cgrp=default sched=0/0 handle=0x72bf067548
  | state=S schedstat=( 4967027138742 9038079370156 24014430 ) utm=334953 stm=161749 core=5 HZ=100
  | stack=0x7fc6a43000-0x7fc6a45000 stackSize=8MB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.onWakefulnessChanged(ActivityManagerService.java:13827)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.am.ActivityManagerService$LocalService.onWakefulnessChanged(ActivityManagerService.java:27222)
  at com.android.server.power.Notifier$1.run(Notifier.java:371)
  at android.os.Handler.handleCallback(Handler.java:873)
  at android.os.Handler.dispatchMessage(Handler.java:99)
  at android.os.Looper.loop(Looper.java:207)
  at com.android.server.SystemServer.run(SystemServer.java:471)
  at com.android.server.SystemServer.main(SystemServer.java:309)
  at java.lang.reflect.Method.invoke(Native method)
  at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:547)
  at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:856)

"Binder:read-perf-event" prio=5 tid=3 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc2b00 self=0x7239616400
  | sysTid=1480 nice=-10 cgrp=default sched=0/0 handle=0x7221ea24f0
  | state=S schedstat=( 126000343552 320788749491 1769736 ) utm=7931 stm=4669 core=6 HZ=100
  | stack=0x7221d9f000-0x7221da1000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: poll_schedule_timeout+0x44/0x7c
  kernel: do_sys_poll+0x3a8/0x500
  kernel: SyS_ppoll+0x1f8/0x22c
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e5f0  /system/lib64/libc.so (__ppoll+8)
  native: #01 pc 000000000002ba20  /system/lib64/libc.so (poll+88)
  native: #02 pc 00000000001a7168  /system/lib64/libandroid_runtime.so (android::os::statistics::PerfEventReporter::waitForPerfEventArrived(_JNIEnv*, int)+184)
  at android.os.statistics.PerfEventReporter.waitForPerfEventArrived(Native method)
  at android.os.statistics.PerfEventReporter.access$000(PerfEventReporter.java:28)
  at android.os.statistics.PerfEventReporter$ProcPerfEventReaderThread.loopOnce(PerfEventReporter.java:97)
  at android.os.statistics.PerfEventReporter$ProcPerfEventReaderThread.run(PerfEventReporter.java:83)

"Binder:filter-perf-event" prio=5 tid=4 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc2da0 self=0x723973c800
  | sysTid=1479 nice=-4 cgrp=default sched=0/0 handle=0x7221fa84f0
  | state=S schedstat=( 439811586770 334446202709 671087 ) utm=31269 stm=12712 core=5 HZ=100
  | stack=0x7221ea5000-0x7221ea7000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.os.Parcel.writeStringArray(Parcel.java:1271)
  at android.os.statistics.ParcelUtils.writeStringArray(ParcelUtils.java:27)
  at android.os.statistics.MonitorSuperviser$SingleMonitorWaitFields.writeToParcel(MonitorSuperviser.java:123)
  at android.os.statistics.PerfEvent.writeToParcel(PerfEvent.java:86)
  at android.os.statistics.PerfEventReporter$ProcPerfEventFilterThread.sendPerfEvent(PerfEventReporter.java:344)
  at android.os.statistics.PerfEventReporter$ProcPerfEventFilterThread.sendPerfEvents(PerfEventReporter.java:323)
  at android.os.statistics.PerfEventReporter$ProcPerfEventFilterThread.sendPerfEvents(PerfEventReporter.java:310)
  at android.os.statistics.PerfEventReporter$ProcPerfEventFilterThread.loopOnce(PerfEventReporter.java:271)
  at android.os.statistics.PerfEventReporter$ProcPerfEventFilterThread.run(PerfEventReporter.java:226)

"ADB-JDWP Connection Control Thread" daemon prio=0 tid=5 WaitingForGcToComplete
  | group="system" sCount=1 dsCount=0 flags=1 obj=0x13fc3068 self=0x723966bc00
  | sysTid=1478 nice=0 cgrp=default sched=0/0 handle=0x72329014f0
  | state=S schedstat=( 18059319 11155416 262 ) utm=0 stm=1 core=7 HZ=100
  | stack=0x7232806000-0x7232808000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e850  /system/lib64/libart.so (artAllocObjectFromCodeInitializedRegionTLAB+380)
  native: #06 pc 000000000056465c  /system/lib64/libart.so (art_quick_alloc_object_initialized_region_tlab+108)
  at java.util.HashMap.values(HashMap.java:959)
  at org.apache.harmony.dalvik.ddmc.DdmServer.broadcast(DdmServer.java:111)
  - locked <0x00e51f9f> (a java.util.HashMap)

"ReferenceQueueDaemon" daemon prio=5 tid=6 Waiting
  | group="system" sCount=1 dsCount=0 flags=1 obj=0x13fc30f0 self=0x7239668000
  | sysTid=1481 nice=4 cgrp=default sched=0/0 handle=0x7221d9c4f0
  | state=S schedstat=( 463515137709 480526413413 1305328 ) utm=35075 stm=11276 core=5 HZ=100
  | stack=0x7221c99000-0x7221c9b000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x0e7fa232> (a java.lang.Class<java.lang.ref.ReferenceQueue>)
  at java.lang.Daemons$ReferenceQueueDaemon.runInternal(Daemons.java:180)
  - locked <0x0e7fa232> (a java.lang.Class<java.lang.ref.ReferenceQueue>)
  at java.lang.Daemons$Daemon.run(Daemons.java:105)
  at java.lang.Thread.run(Thread.java:764)

"FinalizerDaemon" daemon prio=5 tid=7 Waiting
  | group="system" sCount=1 dsCount=0 flags=1 obj=0x13fc3178 self=0x7239668c00
  | sysTid=1482 nice=4 cgrp=default sched=0/0 handle=0x7221c964f0
  | state=S schedstat=( 450932852973 673851320855 5728351 ) utm=21992 stm=23101 core=5 HZ=100
  | stack=0x7221b93000-0x7221b95000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x046f7b83> (a java.lang.Object)
  at java.lang.Object.wait(Object.java:422)
  at java.lang.ref.ReferenceQueue.remove(ReferenceQueue.java:188)
  - locked <0x046f7b83> (a java.lang.Object)
  at java.lang.ref.ReferenceQueue.remove(ReferenceQueue.java:209)
  at java.lang.Daemons$FinalizerDaemon.runInternal(Daemons.java:234)
  at java.lang.Daemons$Daemon.run(Daemons.java:105)
  at java.lang.Thread.run(Thread.java:764)

"FinalizerWatchdogDaemon" daemon prio=5 tid=8 Waiting
  | group="system" sCount=1 dsCount=0 flags=1 obj=0x13fc3200 self=0x7239669800
  | sysTid=1483 nice=4 cgrp=default sched=0/0 handle=0x7221b904f0
  | state=S schedstat=( 1487711817 7773744208 22716 ) utm=100 stm=48 core=5 HZ=100
  | stack=0x7221a8d000-0x7221a8f000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x056bb100> (a java.lang.Daemons$FinalizerWatchdogDaemon)
  at java.lang.Daemons$FinalizerWatchdogDaemon.sleepUntilNeeded(Daemons.java:299)
  - locked <0x056bb100> (a java.lang.Daemons$FinalizerWatchdogDaemon)
  at java.lang.Daemons$FinalizerWatchdogDaemon.runInternal(Daemons.java:279)
  at java.lang.Daemons$Daemon.run(Daemons.java:105)
  at java.lang.Thread.run(Thread.java:764)

"HeapTaskDaemon" daemon prio=5 tid=9 WaitingForGcThreadFlip
  | group="system" sCount=1 dsCount=0 flags=1 obj=0x13fc3290 self=0x723966b000
  | sysTid=1484 nice=4 cgrp=default sched=0/0 handle=0x7221a8a4f0
  | state=S schedstat=( 43488337091560 16871213834680 17940153 ) utm=4217942 stm=130891 core=5 HZ=100
  | stack=0x7221987000-0x7221989000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0d50  /system/lib64/libart.so (art::gc::Heap::ThreadFlipBegin(art::Thread*)+436) // at art/runtime/gc/heap.cc:845
  native: #03 pc 00000000004aa200  /system/lib64/libart.so (art::ThreadList::FlipThreadRoots(art::Closure*, art::Closure*, art::gc::collector::GarbageCollector*, art::gc::GcPauseListener*)+156)
  native: #04 pc 00000000001bdcc0  /system/lib64/libart.so (art::gc::collector::ConcurrentCopying::FlipThreadRoots()+216)
  native: #05 pc 00000000001bcc4c  /system/lib64/libart.so (art::gc::collector::ConcurrentCopying::RunPhases()+1076)
  native: #06 pc 00000000001d2f7c  /system/lib64/libart.so (art::gc::collector::GarbageCollector::Run(art::gc::GcCause, bool)+320)
  native: #07 pc 00000000001f5938  /system/lib64/libart.so (art::gc::Heap::CollectGarbageInternal(art::gc::collector::GcType, art::gc::GcCause, bool)+3408)
  native: #08 pc 0000000000206eb4  /system/lib64/libart.so (art::gc::Heap::ConcurrentGC(art::Thread*, art::gc::GcCause, bool)+128)
  native: #09 pc 000000000020c520  /system/lib64/libart.so (art::gc::Heap::ConcurrentGCTask::Run(art::Thread*)+40)
  native: #10 pc 000000000022e928  /system/lib64/libart.so (art::gc::TaskProcessor::RunAllTasks(art::Thread*)+68)
  at dalvik.system.VMRuntime.runHeapTasks(Native method)
  at java.lang.Daemons$HeapTaskDaemon.runInternal(Daemons.java:477)
  at java.lang.Daemons$Daemon.run(Daemons.java:105)
  at java.lang.Thread.run(Thread.java:764)

"Binder:1471_1" prio=5 tid=10 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3318 self=0x7232a15800
  | sysTid=1524 nice=0 cgrp=default sched=0/0 handle=0x721ea154f0
  | state=S schedstat=( 5428373181009 5397927782624 12342041 ) utm=457810 stm=85027 core=5 HZ=100
  | stack=0x721e91a000-0x721e91c000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_2" prio=5 tid=11 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc33a0 self=0x722f414000
  | sysTid=1525 nice=0 cgrp=default sched=0/0 handle=0x721e9174f0
  | state=S schedstat=( 5685270523273 5586667377684 12578721 ) utm=480700 stm=87827 core=6 HZ=100
  | stack=0x721e81c000-0x721e81e000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"android.bg" prio=5 tid=13 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3428 self=0x7232239400
  | sysTid=1673 nice=0 cgrp=default sched=0/0 handle=0x721da8e4f0
  | state=S schedstat=( 19417818968810 14397831932031 20757829 ) utm=561393 stm=1380388 core=5 HZ=100
  | stack=0x721d98b000-0x721d98d000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.broadcastIntent(ActivityManagerService.java:22705)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.ContextImpl.sendBroadcastAsUser(ContextImpl.java:1195)
  at com.android.server.location.GnssLocationProvider.reportStatus(GnssLocationProvider.java:1766)
  at com.android.server.location.GnssLocationProvider.native_stop(Native method)
  at com.android.server.location.GnssLocationProvider.stopNavigating(GnssLocationProvider.java:1607)
  at com.android.server.location.GnssLocationProvider.updateRequirements(GnssLocationProvider.java:1405)
  at com.android.server.location.GnssLocationProvider.handleSetRequest(GnssLocationProvider.java:1345)
  at com.android.server.location.GnssLocationProvider.access$4100(GnssLocationProvider.java:112)
  at com.android.server.location.GnssLocationProvider$ProviderHandler.handleMessage(GnssLocationProvider.java:2400)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ActivityManager" prio=5 tid=14 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc37e0 self=0x722b77a000
  | sysTid=1675 nice=-2 cgrp=default sched=0/0 handle=0x721d9884f0
  | state=S schedstat=( 5359057294182 7272128320860 16575814 ) utm=297967 stm=237938 core=6 HZ=100
  | stack=0x721d885000-0x721d887000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.idleUids(ActivityManagerService.java:26399)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.am.ActivityManagerService$MainHandler.handleMessage(ActivityManagerService.java:2641)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"android.ui" prio=5 tid=15 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc39c0 self=0x722b77ac00
  | sysTid=1676 nice=-2 cgrp=default sched=0/0 handle=0x721d8824f0
  | state=S schedstat=( 11025066407897 10149490185159 29979350 ) utm=960586 stm=141920 core=7 HZ=100
  | stack=0x721d77f000-0x721d781000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)
  at com.android.server.UiThread.run(UiThread.java:43)

"ActivityManager:procStart" prio=5 tid=16 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3b38 self=0x722b77b800
  | sysTid=1677 nice=-2 cgrp=default sched=0/0 handle=0x721d77c4f0
  | state=S schedstat=( 15190887 45854113 298 ) utm=1 stm=0 core=5 HZ=100
  | stack=0x721d679000-0x721d67b000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"ActivityManager:kill" prio=5 tid=17 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3c50 self=0x722b77c400
  | sysTid=1678 nice=-2 cgrp=default sched=0/0 handle=0x721d6764f0
  | state=S schedstat=( 561092513706 1211251495113 3372116 ) utm=21218 stm=34891 core=5 HZ=100
  | stack=0x721d573000-0x721d575000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"batterystats-worker" prio=5 tid=18 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3dc8 self=0x722b784c00
  | sysTid=1684 nice=0 cgrp=default sched=0/0 handle=0x721d5704f0
  | state=S schedstat=( 557932044045 535019622946 604676 ) utm=24616 stm=31177 core=5 HZ=100
  | stack=0x721d46d000-0x721d46f000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.BatteryExternalStatsWorker.updateExternalStatsLocked(BatteryExternalStatsWorker.java:443)
  - waiting to lock <0x041ad489> (a com.android.internal.os.BatteryStatsImpl) held by thread 24
  at com.android.server.am.BatteryExternalStatsWorker.access$900(BatteryExternalStatsWorker.java:59)
  at com.android.server.am.BatteryExternalStatsWorker$1.run(BatteryExternalStatsWorker.java:354)
  - locked <0x07246c8e> (a java.lang.Object)
  at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:458)
  at java.util.concurrent.FutureTask.run(FutureTask.java:266)
  at java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:301)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1167)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)

"FileObserver" prio=5 tid=19 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3f38 self=0x722b786400
  | sysTid=1687 nice=0 cgrp=default sched=0/0 handle=0x721d1014f0
  | state=S schedstat=( 13586869718 34462191035 170516 ) utm=890 stm=468 core=5 HZ=100
  | stack=0x721cffe000-0x721d000000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: wait_woken+0x44/0x9c
  kernel: inotify_read+0x278/0x4a4
  kernel: __vfs_read+0x38/0x12c
  kernel: vfs_read+0xcc/0x2c8
  kernel: SyS_read+0x50/0xb0
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006eff4  /system/lib64/libc.so (read+4)
  native: #01 pc 0000000000192828  /system/lib64/libandroid_runtime.so (android::android_os_fileobserver_observe(_JNIEnv*, _jobject*, int)+260)
  at android.os.FileObserver$ObserverThread.observe(Native method)
  at android.os.FileObserver$ObserverThread.run(FileObserver.java:86)

"android.fg" prio=5 tid=20 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3fc8 self=0x721d267000
  | sysTid=1688 nice=0 cgrp=default sched=0/0 handle=0x721cffb4f0
  | state=S schedstat=( 262779651287 1402105510552 2504910 ) utm=16957 stm=9320 core=6 HZ=100
  | stack=0x721cef8000-0x721cefa000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.monitor(ActivityManagerService.java:26989)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.Watchdog$HandlerChecker.run(Watchdog.java:358)
  at android.os.Handler.handleCallback(Handler.java:873)
  at android.os.Handler.dispatchMessage(Handler.java:99)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"android.io" prio=5 tid=21 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc40e0 self=0x721d267c00
  | sysTid=1689 nice=0 cgrp=default sched=0/0 handle=0x721cef54f0
  | state=S schedstat=( 601018186229 1017339631209 1488870 ) utm=35692 stm=24409 core=6 HZ=100
  | stack=0x721cdf2000-0x721cdf4000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e690  /system/lib64/libart.so (artAllocObjectFromCodeResolvedRegionTLAB+544)
  native: #06 pc 0000000000564570  /system/lib64/libart.so (art_quick_alloc_object_resolved_region_tlab+112)
  at android.os.Message.recycleUnchecked(Message.java:314)
  at android.os.Looper.loop(Looper.java:254)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"android.display" prio=5 tid=22 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1414a8c8 self=0x721d268800
  | sysTid=1690 nice=-3 cgrp=default sched=0/0 handle=0x721cdef4f0
  | state=S schedstat=( 1957958743390 7067261735681 19971654 ) utm=123229 stm=72566 core=5 HZ=100
  | stack=0x721ccec000-0x721ccee000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService$LocalService.clearSavedANRState(ActivityManagerService.java:27588)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.wm.WindowManagerService$H.handleMessage(WindowManagerService.java:5259)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"CpuTracker" prio=5 tid=23 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc41f8 self=0x721d269400
  | sysTid=1691 nice=0 cgrp=default sched=0/0 handle=0x721cce94f0
  | state=S schedstat=( 150441514464 86003978678 86690 ) utm=2146 stm=12898 core=6 HZ=100
  | stack=0x721cbe6000-0x721cbe8000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e850  /system/lib64/libart.so (artAllocObjectFromCodeInitializedRegionTLAB+380)
  native: #06 pc 000000000056465c  /system/lib64/libart.so (art_quick_alloc_object_initialized_region_tlab+108)
  at android.os.StrictMode.allowThreadDiskReads(StrictMode.java:1198)
  at com.android.internal.os.ProcessCpuTracker.update(ProcessCpuTracker.java:386)
  at com.android.server.am.ActivityManagerService.updateCpuStatsNow(ActivityManagerService.java:3436)
  - locked <0x0424a243> (a com.android.internal.os.ProcessCpuTracker)
  at com.android.server.am.ActivityManagerService$5.run(ActivityManagerService.java:3273)

"PowerManagerService" prio=5 tid=24 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc4290 self=0x721d26a000
  | sysTid=1692 nice=-4 cgrp=default sched=0/0 handle=0x721cbe34f0
  | state=S schedstat=( 434959457252 1420519010942 7303299 ) utm=25675 stm=17820 core=6 HZ=100
  | stack=0x721cae0000-0x721cae2000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 0000000000127778  /system/lib64/libandroid_runtime.so (JHwParcel_native_writeInterfaceToken(_JNIEnv*, _jobject*, _jstring*)+72)
  at android.os.HwParcel.writeInterfaceToken(Native method)
  at android.hardware.health.V2_0.IHealth$Proxy.update(IHealth.java:355)
  at com.android.server.BatteryService$BatteryPropertiesRegistrar.scheduleUpdate(BatteryService.java:1317)
  at com.android.internal.os.BatteryStatsImpl.updateBatteryPropertiesLocked(BatteryStatsImpl.java:4038)
  at com.android.internal.os.BatteryStatsImpl.updateTimeBasesLocked(BatteryStatsImpl.java:4001)
  at com.android.internal.os.BatteryStatsImpl.noteScreenStateLocked(BatteryStatsImpl.java:5053)
  at com.android.server.am.BatteryStatsService.noteScreenState(BatteryStatsService.java:653)
  - locked <0x041ad489> (a com.android.internal.os.BatteryStatsImpl)
  at com.android.server.display.DisplayPowerController.setScreenState(DisplayPowerController.java:1169)
  at com.android.server.display.DisplayPowerController.setScreenState(DisplayPowerController.java:1143)
  at com.android.server.display.DisplayPowerController.animateScreenStateChange(DisplayPowerController.java:1405)
  at com.android.server.display.DisplayPowerController.updatePowerState(DisplayPowerController.java:788)
  at com.android.server.display.DisplayPowerController.access$500(DisplayPowerController.java:81)
  at com.android.server.display.DisplayPowerController$DisplayControllerHandler.handleMessage(DisplayPowerController.java:1830)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"BatteryStats_wakeupReason" prio=5 tid=25 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc43a8 self=0x721d26ac00
  | sysTid=1693 nice=-2 cgrp=default sched=0/0 handle=0x721cadd4f0
  | state=S schedstat=( 18961728 4574011 223 ) utm=1 stm=0 core=7 HZ=100
  | stack=0x721c9da000-0x721c9dc000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 000000000002248c  /system/lib64/libc.so (__futex_wait_ex(void volatile*, bool, int, bool, timespec const*)+140)
  native: #02 pc 000000000002cf60  /system/lib64/libc.so (sem_wait+116)
  native: #03 pc 0000000000047f00  /system/lib64/libandroid_servers.so (android::nativeWaitWakeup(_JNIEnv*, _jobject*, _jobject*)+120)
  at com.android.server.am.BatteryStatsService.nativeWaitWakeup(Native method)
  at com.android.server.am.BatteryStatsService.access$100(BatteryStatsService.java:82)
  at com.android.server.am.BatteryStatsService$WakeupReasonThread.waitWakeup(BatteryStatsService.java:1217)
  at com.android.server.am.BatteryStatsService$WakeupReasonThread.run(BatteryStatsService.java:1202)

"work-thread" prio=5 tid=26 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc49b0 self=0x7232ada800
  | sysTid=1694 nice=0 cgrp=default sched=0/0 handle=0x721c9d74f0
  | state=S schedstat=( 27286726 70445196 379 ) utm=0 stm=2 core=5 HZ=100
  | stack=0x721c8d4000-0x721c8d6000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"PackageManager" prio=5 tid=27 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc4ac8 self=0x721d26b800
  | sysTid=1695 nice=10 cgrp=default sched=0/0 handle=0x721c8d14f0
  | state=S schedstat=( 15165201 189271890 304 ) utm=1 stm=0 core=7 HZ=100
  | stack=0x721c7ce000-0x721c7d0000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"PackageManager" prio=5 tid=28 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc4be0 self=0x721d26c400
  | sysTid=1696 nice=10 cgrp=default sched=0/0 handle=0x721c7cb4f0
  | state=S schedstat=( 96871751671 151298813938 211104 ) utm=5161 stm=4526 core=7 HZ=100
  | stack=0x721c6c8000-0x721c6ca000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"PackageInstaller" prio=5 tid=30 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc4cf8 self=0x721d35dc00
  | sysTid=1817 nice=0 cgrp=default sched=0/0 handle=0x721c2f94f0
  | state=S schedstat=( 724204599 46985934 409 ) utm=62 stm=10 core=5 HZ=100
  | stack=0x721c1f6000-0x721c1f8000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"android.anim" prio=5 tid=31 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc4e10 self=0x721d35e800
  | sysTid=1821 nice=-10 cgrp=default sched=0/0 handle=0x721c1f34f0
  | state=S schedstat=( 36605508909013 18726684321143 55818859 ) utm=3133806 stm=526744 core=5 HZ=100
  | stack=0x721c0f0000-0x721c0f2000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"android.anim.lf" prio=5 tid=32 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc4f28 self=0x721d35f400
  | sysTid=1822 nice=-10 cgrp=default sched=0/0 handle=0x721c0ed4f0
  | state=S schedstat=( 4719371572173 3699387464410 20328143 ) utm=318949 stm=152988 core=5 HZ=100
  | stack=0x721bfea000-0x721bfec000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"HwBinder:1471_1" prio=5 tid=35 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc5040 self=0x722b7ab800
  | sysTid=1825 nice=0 cgrp=default sched=0/0 handle=0x721baf94f0
  | state=S schedstat=( 30959031225 48368252069 199192 ) utm=2051 stm=1044 core=6 HZ=100
  | stack=0x721b9fe000-0x721ba00000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 0000000000128c5c  /system/lib64/libandroid_runtime.so (JHwParcel_native_enforceInterface(_JNIEnv*, _jobject*, _jstring*)+72)
  at android.os.HwParcel.enforceInterface(Native method)
  at android.hardware.wifi.supplicant.V1_1.ISupplicantStaIfaceCallback$Stub.onTransact(ISupplicantStaIfaceCallback.java:1042)

"UEventObserver" prio=5 tid=36 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff2988 self=0x721d363000
  | sysTid=1826 nice=0 cgrp=default sched=0/0 handle=0x721b9fb4f0
  | state=S schedstat=( 19810165177 143355196970 218423 ) utm=570 stm=1411 core=7 HZ=100
  | stack=0x721b8f8000-0x721b8fa000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 0000000000182260  /system/lib64/libart.so (art::mirror::Object* art::gc::Heap::AllocObjectWithAllocator<true, true, art::mirror::SetStringCountVisitor>(art::Thread*, art::ObjPtr<art::mirror::Class>, unsigned long, art::gc::AllocatorType, art::mirror::SetStringCountVisitor const&)+736)
  native: #06 pc 00000000003af1d8  /system/lib64/libart.so (art::mirror::String::AllocFromUtf16(art::Thread*, int, unsigned short const*)+308)
  native: #07 pc 000000000036ae84  /system/lib64/libart.so (art::JNI::NewString(_JNIEnv*, unsigned short const*, int)+616)
  native: #08 pc 0000000000130e10  /system/lib64/libandroid_runtime.so (android::nativeWaitForNextEvent(_JNIEnv*, _jclass*)+408)
  at android.os.UEventObserver.nativeWaitForNextEvent(Native method)
  at android.os.UEventObserver.access$100(UEventObserver.java:41)
  at android.os.UEventObserver$UEventThread.run(UEventObserver.java:182)

"HealthServiceRefresh" prio=5 tid=37 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff2c18 self=0x721d363c00
  | sysTid=1828 nice=0 cgrp=default sched=0/0 handle=0x721b8f54f0
  | state=S schedstat=( 15375584 43971868 307 ) utm=1 stm=0 core=5 HZ=100
  | stack=0x721b7f2000-0x721b7f4000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"AccountManagerService" prio=5 tid=38 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff2d30 self=0x721d364800
  | sysTid=1830 nice=-2 cgrp=default sched=0/0 handle=0x721b7ef4f0
  | state=S schedstat=( 7390346845 29795666708 68408 ) utm=269 stm=470 core=5 HZ=100
  | stack=0x721b6ec000-0x721b6ee000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"SettingsProvider" prio=5 tid=39 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff2e48 self=0x721d36a000
  | sysTid=1833 nice=10 cgrp=default sched=0/0 handle=0x721b57f4f0
  | state=S schedstat=( 103555188779 713863121302 338182 ) utm=5280 stm=5075 core=5 HZ=100
  | stack=0x721b47c000-0x721b47e000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"AlarmManager" prio=5 tid=40 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff2f60 self=0x721d36ac00
  | sysTid=1836 nice=0 cgrp=default sched=0/0 handle=0x721b4794f0
  | state=S schedstat=( 138985139854 148409210249 305644 ) utm=8455 stm=5443 core=5 HZ=100
  | stack=0x721b376000-0x721b378000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.PendingIntentRecord.sendInner(PendingIntentRecord.java:256)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.am.PendingIntentRecord.sendWithResult(PendingIntentRecord.java:245)
  at com.android.server.am.ActivityManagerService.sendIntentSender(ActivityManagerService.java:8827)
  at android.app.PendingIntent.sendAndReturnResult(PendingIntent.java:892)
  at android.app.PendingIntent.send(PendingIntent.java:874)
  at com.android.server.AlarmManagerService$DeliveryTracker.deliverLocked(AlarmManagerService.java:4204)
  at com.android.server.AlarmManagerService.deliverAlarmsLocked(AlarmManagerService.java:3454)
  at com.android.server.AlarmManagerService$AlarmThread.run(AlarmManagerService.java:3593)
  - locked <0x02951623> (a java.lang.Object)

"SensorService" prio=10 tid=41 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff3180 self=0x72163fe400
  | sysTid=1864 nice=-8 cgrp=default sched=1073741825/10 handle=0x721b2754f0
  | state=S schedstat=( 3507690058745 65741678065 24904567 ) utm=126964 stm=223805 core=6 HZ=100
  | stack=0x721b17a000-0x721b17c000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: binder_thread_read+0xa78/0x11a0
  kernel: binder_ioctl+0x920/0xb08
  kernel: do_vfs_ioctl+0xb8/0x8d8
  kernel: SyS_ioctl+0x84/0x98
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e5bc  /system/lib64/libc.so (__ioctl+4)
  native: #01 pc 0000000000029544  /system/lib64/libc.so (ioctl+136)
  native: #02 pc 000000000001e22c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::talkWithDriver(bool)+240)
  native: #03 pc 000000000001e77c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::waitForResponse(android::hardware::Parcel*, int*)+60)
  native: #04 pc 0000000000012204  /system/lib64/libhwbinder.so (android::hardware::BpHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+312)
  native: #05 pc 000000000000e0d0  /system/lib64/android.hardware.sensors@1.0.so (android::hardware::sensors::V1_0::BpHwSensors::_hidl_poll(android::hardware::IInterface*, android::hardware::details::HidlInstrumentor*, int, std::__1::function<void (android::hardware::sensors::V1_0::Result, android::hardware::hidl_vec<android::hardware::sensors::V1_0::Event> const&, android::hardware::hidl_vec<android::hardware::sensors::V1_0::SensorInfo> const&)>)+228)
  native: #06 pc 000000000000f678  /system/lib64/android.hardware.sensors@1.0.so (android::hardware::sensors::V1_0::BpHwSensors::poll(int, std::__1::function<void (android::hardware::sensors::V1_0::Result, android::hardware::hidl_vec<android::hardware::sensors::V1_0::Event> const&, android::hardware::hidl_vec<android::hardware::sensors::V1_0::SensorInfo> const&)>)+140)
  native: #07 pc 0000000000016d5c  /system/lib64/libsensorservice.so (android::SensorDevice::poll(sensors_event_t*, unsigned long)+164)
  native: #08 pc 0000000000024484  /system/lib64/libsensorservice.so (android::SensorService::threadLoop()+280)
  native: #09 pc 0000000000024d70  /system/lib64/libsensorservice.so (non-virtual thunk to android::SensorService::threadLoop()+12)
  native: #10 pc 000000000000faf4  /system/lib64/libutils.so (android::Thread::_threadLoop(void*)+280)
  native: #11 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #12 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #13 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"SensorEventAckReceiver" prio=10 tid=42 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff3208 self=0x7232be9000
  | sysTid=1863 nice=-8 cgrp=default sched=0/0 handle=0x721b3734f0
  | state=S schedstat=( 13761196234 20447391788 349954 ) utm=260 stm=1116 core=6 HZ=100
  | stack=0x721b278000-0x721b27a000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 0000000000024f0c  /system/lib64/libsensorservice.so (android::SensorService::SensorEventAckReceiver::threadLoop()+144)
  native: #04 pc 000000000000faf4  /system/lib64/libutils.so (android::Thread::_threadLoop(void*)+280)
  native: #05 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #06 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #07 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"HwBinder:1471_2" prio=5 tid=43 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13ff3290 self=0x721c5cbc00
  | sysTid=1866 nice=0 cgrp=default sched=0/0 handle=0x721b1774f0
  | state=S schedstat=( 30107268437 49117136741 202357 ) utm=1991 stm=1019 core=7 HZ=100
  | stack=0x721b07c000-0x721b07e000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000013dcd4  /system/lib64/libart.so (art::mirror::Object* art::gc::Heap::AllocObjectWithAllocator<true, false, art::VoidFunctor>(art::Thread*, art::ObjPtr<art::gc::Heap::AllocObjectWithAllocator<true, false, art::VoidFunctor>::Class>, unsigned long, art::gc::AllocatorType, art::VoidFunctor const&)+876)
  native: #06 pc 0000000000331840  /system/lib64/libart.so (art::JNI::NewObjectV(_JNIEnv*, _jclass*, _jmethodID*, std::__va_list)+696)
  native: #07 pc 00000000000c4fd0  /system/lib64/libandroid_runtime.so (_JNIEnv::NewObject(_jclass*, _jmethodID*, ...)+120)
  native: #08 pc 0000000000126b80  /system/lib64/libandroid_runtime.so (android::JHwParcel::NewObject(_JNIEnv*)+108)
  native: #09 pc 00000000001216d0  /system/lib64/libandroid_runtime.so (android::JHwBinder::onTransact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+80)
  native: #10 pc 000000000001df34  /system/lib64/libhwbinder.so (android::hardware::BHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+72)
  native: #11 pc 000000000001508c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::executeCommand(int)+1508)
  native: #12 pc 0000000000014938  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::getAndExecuteCommand()+204)
  native: #13 pc 0000000000015708  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::joinThreadPool(bool)+268)
  native: #14 pc 000000000001d530  /system/lib64/libhwbinder.so (android::hardware::PoolThread::threadLoop()+24)
  native: #15 pc 000000000000faf4  /system/lib64/libutils.so (android::Thread::_threadLoop(void*)+280)
  native: #16 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #17 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #18 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"HwBinder:1471_3" prio=5 tid=44 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14022580 self=0x7232bf0800
  | sysTid=1868 nice=0 cgrp=default sched=0/0 handle=0x721af7b4f0
  | state=S schedstat=( 38538622312 63739005383 252887 ) utm=2532 stm=1321 core=7 HZ=100
  | stack=0x721ae80000-0x721ae82000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000013dcd4  /system/lib64/libart.so (art::mirror::Object* art::gc::Heap::AllocObjectWithAllocator<true, false, art::VoidFunctor>(art::Thread*, art::ObjPtr<art::gc::Heap::AllocObjectWithAllocator<true, false, art::VoidFunctor>::Class>, unsigned long, art::gc::AllocatorType, art::VoidFunctor const&)+876)
  native: #06 pc 0000000000331840  /system/lib64/libart.so (art::JNI::NewObjectV(_JNIEnv*, _jclass*, _jmethodID*, std::__va_list)+696)
  native: #07 pc 00000000000c4fd0  /system/lib64/libandroid_runtime.so (_JNIEnv::NewObject(_jclass*, _jmethodID*, ...)+120)
  native: #08 pc 0000000000126b80  /system/lib64/libandroid_runtime.so (android::JHwParcel::NewObject(_JNIEnv*)+108)
  native: #09 pc 00000000001216d0  /system/lib64/libandroid_runtime.so (android::JHwBinder::onTransact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+80)
  native: #10 pc 000000000001df34  /system/lib64/libhwbinder.so (android::hardware::BHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+72)
  native: #11 pc 000000000001508c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::executeCommand(int)+1508)
  native: #12 pc 0000000000014938  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::getAndExecuteCommand()+204)
  native: #13 pc 0000000000015708  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::joinThreadPool(bool)+268)
  native: #14 pc 000000000001d530  /system/lib64/libhwbinder.so (android::hardware::PoolThread::threadLoop()+24)
  native: #15 pc 000000000000faf4  /system/lib64/libutils.so (android::Thread::_threadLoop(void*)+280)
  native: #16 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #17 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #18 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"hidl_ssvc_poll" prio=5 tid=45 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405e020 self=0x7214a55400
  | sysTid=1867 nice=0 cgrp=default sched=1/10 handle=0x721b0794f0
  | state=S schedstat=( 1674990425380 20398966129 18227662 ) utm=50896 stm=116603 core=7 HZ=100
  | stack=0x721af7e000-0x721af80000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 00000000000148d8  /system/lib64/libutils.so (android::Looper::pollAll(int, int*, int*, void**)+288)
  native: #03 pc 000000000000a698  /system/lib64/libsensorservicehidl.so (_ZNSt3__114__thread_proxyINS_5tupleIJNS_10unique_ptrINS_15__thread_structENS_14default_deleteIS3_EEEEZN7android10frameworks13sensorservice4V1_014implementation13SensorManager9getLooperEvE3$_2EEEEEPvSF_+308)
  native: #04 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #05 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"InputDispatcher" prio=10 tid=46 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405e0a8 self=0x7232be0000
  | sysTid=1871 nice=-8 cgrp=default sched=0/0 handle=0x721ae7d4f0
  | state=S schedstat=( 6114678136036 5604957289411 42818553 ) utm=340437 stm=271030 core=6 HZ=100
  | stack=0x721ad82000-0x721ad84000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.getAllStackInfos(ActivityManagerService.java:12058)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.policy.BaseMiuiPhoneWindowManager.exitFreeFormWindowIfNeeded(BaseMiuiPhoneWindowManager.java:560)
  at com.android.server.policy.BaseMiuiPhoneWindowManager.interceptKeyBeforeDispatching(BaseMiuiPhoneWindowManager.java:586)
  at com.android.server.wm.InputMonitor.interceptKeyBeforeDispatching(InputMonitor.java:484)
  at com.android.server.input.InputManagerService.interceptKeyBeforeDispatching(InputManagerService.java:2005)

"InputReader" prio=10 tid=47 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405e130 self=0x7214a75c00
  | sysTid=1872 nice=-8 cgrp=default sched=0/0 handle=0x721ad7f4f0
  | state=S schedstat=( 7908204071 4698661062 42116 ) utm=195 stm=595 core=6 HZ=100
  | stack=0x721ac84000-0x721ac86000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.BatteryStatsService.noteStartWakelock(BatteryStatsService.java:503)
  - waiting to lock <0x041ad489> (a com.android.internal.os.BatteryStatsImpl) held by thread 24
  at com.android.server.power.Notifier.onWakeLockAcquired(Notifier.java:213)
  at com.android.server.power.PowerManagerService.notifyWakeLockAcquiredLocked(PowerManagerService.java:1183)
  at com.android.server.power.PowerManagerService.acquireWakeLockInternal(PowerManagerService.java:1029)
  - locked <0x00f03a2e> (a java.lang.Object)
  at com.android.server.power.PowerManagerService.access$3300(PowerManagerService.java:118)
  at com.android.server.power.PowerManagerService$BinderService.acquireWakeLock(PowerManagerService.java:4246)
  at android.os.PowerManager$WakeLock.acquireLocked(PowerManager.java:1509)
  at android.os.PowerManager$WakeLock.acquire(PowerManager.java:1475)
  - locked <0x0fdbb0c0> (a android.os.Binder)
  at com.android.server.policy.PhoneWindowManager.interceptPowerKeyDown(PhoneWindowManager.java:1391)
  at com.android.server.policy.PhoneWindowManager.interceptKeyBeforeQueueing(PhoneWindowManager.java:6549)
  at com.android.server.policy.MiuiPhoneWindowManager.callSuperInterceptKeyBeforeQueueing(MiuiPhoneWindowManager.java:255)
  at com.android.server.policy.BaseMiuiPhoneWindowManager.interceptKeyBeforeQueueingInternal(BaseMiuiPhoneWindowManager.java:1209)
  at com.android.server.policy.MiuiPhoneWindowManager.interceptKeyBeforeQueueing(MiuiPhoneWindowManager.java:241)
  at com.android.server.wm.InputMonitor.interceptKeyBeforeQueueing(InputMonitor.java:466)
  at com.android.server.input.InputManagerService.interceptKeyBeforeQueueing(InputManagerService.java:1993)

"NetworkWatchlistService" prio=5 tid=48 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405e1b8 self=0x721d36b800
  | sysTid=1873 nice=10 cgrp=default sched=0/0 handle=0x721ac814f0
  | state=S schedstat=( 310379570214 1835112156308 3864952 ) utm=20638 stm=10399 core=7 HZ=100
  | stack=0x721ab7e000-0x721ab80000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"StorageManagerService" prio=5 tid=49 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405e2d0 self=0x721d36c400
  | sysTid=1876 nice=0 cgrp=default sched=0/0 handle=0x721a5204f0
  | state=S schedstat=( 19465206 41608076 331 ) utm=1 stm=0 core=7 HZ=100
  | stack=0x721a41d000-0x721a41f000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"NetdConnector" prio=5 tid=50 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405e3e8 self=0x721c426000
  | sysTid=1877 nice=0 cgrp=default sched=0/0 handle=0x72195704f0
  | state=S schedstat=( 148628867247 230035610593 1077697 ) utm=11733 stm=3129 core=6 HZ=100
  | stack=0x721946d000-0x721946f000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050f738  /system/lib64/libart.so (artAllocStringFromCharsFromCodeRegionTLAB+1324)
  native: #06 pc 0000000000563e88  /system/lib64/libart.so (art_quick_alloc_string_from_chars_region_tlab+56)
  at java.lang.StringFactory.newStringFromChars(StringFactory.java:267)
  at java.lang.StringFactory.newStringFromBytes(StringFactory.java:252)
  at com.android.server.NativeDaemonConnector.listenToSocket(NativeDaemonConnector.java:228)
  at com.android.server.NativeDaemonConnector.run(NativeDaemonConnector.java:139)
  at java.lang.Thread.run(Thread.java:764)

"NetworkStats" prio=5 tid=51 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405f560 self=0x721c427800
  | sysTid=1879 nice=0 cgrp=default sched=0/0 handle=0x72178894f0
  | state=S schedstat=( 65379271099 100325714793 164014 ) utm=3891 stm=2646 core=7 HZ=100
  | stack=0x7217786000-0x7217788000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"NetworkPolicy" prio=5 tid=52 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405f678 self=0x721c428400
  | sysTid=1880 nice=0 cgrp=default sched=0/0 handle=0x72177834f0
  | state=S schedstat=( 29660716417 92303710308 133350 ) utm=1533 stm=1433 core=7 HZ=100
  | stack=0x7217680000-0x7217682000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"NetworkPolicy.uid" prio=5 tid=53 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405f790 self=0x72163fc000
  | sysTid=1881 nice=-2 cgrp=default sched=0/0 handle=0x721767d4f0
  | state=S schedstat=( 992941159886 2687927167537 3629569 ) utm=24231 stm=75063 core=5 HZ=100
  | stack=0x721757a000-0x721757c000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService$LocalService.notifyNetworkPolicyRulesUpdated(ActivityManagerService.java:27503)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.net.NetworkPolicyManagerService.handleUidChanged(NetworkPolicyManagerService.java:4461)
  - locked <0x05e68352> (a java.lang.Object)
  at com.android.server.net.NetworkPolicyManagerService$18.handleMessage(NetworkPolicyManagerService.java:4435)
  at android.os.Handler.dispatchMessage(Handler.java:102)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"MiuiNetworkPolicy" prio=5 tid=54 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405fcb0 self=0x72163fcc00
  | sysTid=1882 nice=0 cgrp=default sched=0/0 handle=0x72175774f0
  | state=S schedstat=( 241405141842 960198323555 2093132 ) utm=17084 stm=7056 core=7 HZ=100
  | stack=0x7217474000-0x7217476000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"WifiService" prio=5 tid=55 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405fdc8 self=0x72163fd800
  | sysTid=1883 nice=0 cgrp=default sched=0/0 handle=0x72174714f0
  | state=S schedstat=( 196311890701 146207809136 453626 ) utm=6453 stm=13178 core=6 HZ=100
  | stack=0x721736e000-0x7217370000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e690  /system/lib64/libart.so (artAllocObjectFromCodeResolvedRegionTLAB+544)
  native: #06 pc 0000000000564570  /system/lib64/libart.so (art_quick_alloc_object_resolved_region_tlab+112)
  at android.os.Message.recycleUnchecked(Message.java:314)
  at android.os.Looper.loop(Looper.java:254)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"WifiStateMachine" prio=5 tid=56 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405fee0 self=0x721c426c00
  | sysTid=1884 nice=0 cgrp=default sched=0/0 handle=0x721736b4f0
  | state=S schedstat=( 7635953275542 12617257294041 29670090 ) utm=468797 stm=294798 core=6 HZ=100
  | stack=0x7217268000-0x721726a000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 0000000000127778  /system/lib64/libandroid_runtime.so (JHwParcel_native_writeInterfaceToken(_JNIEnv*, _jobject*, _jstring*)+72)
  at android.os.HwParcel.writeInterfaceToken(Native method)
  at android.hardware.wifi.V1_0.IWifiStaIface$Proxy.getLinkLayerStats(IWifiStaIface.java:1046)
  at com.android.server.wifi.WifiVendorHal.getWifiLinkLayerStats(WifiVendorHal.java:936)
  - locked <0x0769acaf> (a java.lang.Object)
  at com.android.server.wifi.WifiNative.getWifiLinkLayerStats(WifiNative.java:2385)
  at com.android.server.wifi.WifiStateMachine.getWifiLinkLayerStats(WifiStateMachine.java:1345)
  at com.android.server.wifi.WifiStateMachine$L2ConnectedState.processMessage(WifiStateMachine.java:5169)
  at com.android.internal.util.StateMachine$SmHandler.processMsg(StateMachine.java:992)
  at com.android.internal.util.StateMachine$SmHandler.handleMessage(StateMachine.java:809)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"WifiScanningService" prio=5 tid=57 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405fff8 self=0x721c54e800
  | sysTid=1886 nice=0 cgrp=default sched=0/0 handle=0x72172654f0
  | state=S schedstat=( 2020891770796 2234910687581 11106237 ) utm=156397 stm=45692 core=7 HZ=100
  | stack=0x7217162000-0x7217164000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"WifiP2pService" prio=5 tid=58 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14060110 self=0x721c551800
  | sysTid=1887 nice=0 cgrp=default sched=0/0 handle=0x721715f4f0
  | state=S schedstat=( 2508141569 4973263117 23604 ) utm=147 stm=103 core=7 HZ=100
  | stack=0x721705c000-0x721705e000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ConnectivityServiceThread" prio=5 tid=59 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14060228 self=0x721c54dc00
  | sysTid=1888 nice=0 cgrp=default sched=0/0 handle=0x7216dff4f0
  | state=S schedstat=( 119392769592 223767051901 399517 ) utm=7231 stm=4708 core=7 HZ=100
  | stack=0x7216cfc000-0x7216cfe000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"Tethering" prio=5 tid=60 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14060340 self=0x721c552400
  | sysTid=1889 nice=0 cgrp=default sched=0/0 handle=0x7216c654f0
  | state=S schedstat=( 16072239 53052548 308 ) utm=0 stm=1 core=7 HZ=100
  | stack=0x7216b62000-0x7216b64000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"android.pacmanager" prio=5 tid=61 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14060458 self=0x721c562000
  | sysTid=1890 nice=0 cgrp=default sched=0/0 handle=0x7216b5f4f0
  | state=S schedstat=( 13207190 39950100 305 ) utm=1 stm=0 core=6 HZ=100
  | stack=0x7216a5c000-0x7216a5e000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"NsdService" prio=5 tid=62 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14060570 self=0x721c562c00
  | sysTid=1891 nice=0 cgrp=default sched=0/0 handle=0x7216a594f0
  | state=S schedstat=( 14590466 39207915 313 ) utm=0 stm=1 core=6 HZ=100
  | stack=0x7216956000-0x7216958000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"mDnsConnector" prio=5 tid=63 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14060688 self=0x721c563800
  | sysTid=1892 nice=0 cgrp=default sched=0/0 handle=0x72169534f0
  | state=S schedstat=( 12108026 3312083 201 ) utm=0 stm=1 core=6 HZ=100
  | stack=0x7216850000-0x7216852000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: unix_stream_read_generic+0x5a4/0x794
  kernel: unix_stream_recvmsg+0x4c/0x6c
  kernel: sock_recvmsg+0x48/0x58
  kernel: ___sys_recvmsg+0xbc/0x280
  kernel: SyS_recvmsg+0xac/0xdc
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006f084  /system/lib64/libc.so (recvmsg+4)
  native: #01 pc 000000000013442c  /system/lib64/libandroid_runtime.so (android::socket_read_all(_JNIEnv*, _jobject*, int, void*, unsigned long)+112)
  native: #02 pc 0000000000134094  /system/lib64/libandroid_runtime.so (android::socket_readba(_JNIEnv*, _jobject*, _jbyteArray*, int, int, _jobject*)+256)
  at android.net.LocalSocketImpl.readba_native(Native method)
  at android.net.LocalSocketImpl.access$300(LocalSocketImpl.java:36)
  at android.net.LocalSocketImpl$SocketInputStream.read(LocalSocketImpl.java:110)
  - locked <0x055add2c> (a java.lang.Object)
  at com.android.server.NativeDaemonConnector.listenToSocket(NativeDaemonConnector.java:213)
  at com.android.server.NativeDaemonConnector.run(NativeDaemonConnector.java:139)
  at java.lang.Thread.run(Thread.java:764)

"notification-sqlite-log" prio=5 tid=64 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140617d8 self=0x721c564400
  | sysTid=1893 nice=10 cgrp=default sched=0/0 handle=0x72165ff4f0
  | state=S schedstat=( 78623884263 913505890890 472200 ) utm=3613 stm=4249 core=6 HZ=100
  | stack=0x72164fc000-0x72164fe000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ranker" prio=5 tid=65 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140618f0 self=0x721c565000
  | sysTid=1894 nice=10 cgrp=default sched=0/0 handle=0x72161ff4f0
  | state=S schedstat=( 154823052700 835577236769 330796 ) utm=13322 stm=2160 core=6 HZ=100
  | stack=0x72160fc000-0x72160fe000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ConditionProviders.ECP" prio=5 tid=66 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14061a08 self=0x721c565c00
  | sysTid=1895 nice=10 cgrp=default sched=0/0 handle=0x7215dff4f0
  | state=S schedstat=( 18370201 229489944 311 ) utm=1 stm=0 core=7 HZ=100
  | stack=0x7215cfc000-0x7215cfe000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"DeviceStorageMonitorService" prio=5 tid=67 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14061b20 self=0x721c566800
  | sysTid=1896 nice=10 cgrp=default sched=0/0 handle=0x7215cf94f0
  | state=S schedstat=( 12159040641 26550594670 25262 ) utm=559 stm=656 core=6 HZ=100
  | stack=0x7215bf6000-0x7215bf8000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050f738  /system/lib64/libart.so (artAllocStringFromCharsFromCodeRegionTLAB+1324)
  native: #06 pc 0000000000563e88  /system/lib64/libart.so (art_quick_alloc_string_from_chars_region_tlab+56)
  at java.lang.StringBuilder.toString(StringBuilder.java:410)
  at com.android.server.pm.InstructionSets.getDexCodeInstructionSet(InstructionSets.java:78)
  at com.android.server.pm.InstructionSets.getDexCodeInstructionSets(InstructionSets.java:85)
  at com.android.server.pm.InstructionSets.getAllDexCodeInstructionSets(InstructionSets.java:99)
  at com.android.server.storage.DeviceStorageMonitorService.isBootImageOnDisk(DeviceStorageMonitorService.java:366)
  at com.android.server.storage.DeviceStorageMonitorService.check(DeviceStorageMonitorService.java:310)
  at com.android.server.storage.DeviceStorageMonitorService.access$100(DeviceStorageMonitorService.java:81)
  at com.android.server.storage.DeviceStorageMonitorService$2.handleMessage(DeviceStorageMonitorService.java:358)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"LocationPolicy" prio=5 tid=68 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14061c38 self=0x721c567400
  | sysTid=1897 nice=0 cgrp=default sched=0/0 handle=0x7215bf34f0
  | state=S schedstat=( 24364007815 193114234305 474814 ) utm=1265 stm=1171 core=7 HZ=100
  | stack=0x7215af0000-0x7215af2000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ConnectivityThread" prio=5 tid=69 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14061d50 self=0x7216319000
  | sysTid=1898 nice=0 cgrp=default sched=0/0 handle=0x7215aed4f0
  | state=S schedstat=( 4745725183 10273754130 9828 ) utm=375 stm=99 core=6 HZ=100
  | stack=0x72159ea000-0x72159ec000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"AudioService" prio=5 tid=70 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14061e68 self=0x7216319c00
  | sysTid=1899 nice=0 cgrp=default sched=0/0 handle=0x72159e74f0
  | state=S schedstat=( 12337421667 34163948886 187311 ) utm=361 stm=872 core=7 HZ=100
  | stack=0x72158e4000-0x72158e6000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at com.android.server.audio.AudioService$AudioSystemThread.run(AudioService.java:5495)

"miui.fg" prio=5 tid=71 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14061f90 self=0x721631c000
  | sysTid=1904 nice=0 cgrp=default sched=0/0 handle=0x72158e14f0
  | state=S schedstat=( 355087222997 2288108179073 4514314 ) utm=19896 stm=15612 core=6 HZ=100
  | stack=0x72157de000-0x72157e0000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"SecurityWriteHandlerThread" prio=5 tid=72 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140620a8 self=0x721631e400
  | sysTid=1905 nice=10 cgrp=default sched=0/0 handle=0x72157db4f0
  | state=S schedstat=( 3549073688 39634651623 29398 ) utm=173 stm=181 core=6 HZ=100
  | stack=0x72156d8000-0x72156da000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050eb08  /system/lib64/libart.so (artAllocArrayFromCodeResolvedRegionTLAB+628)
  native: #06 pc 0000000000564c88  /system/lib64/libart.so (art_quick_alloc_array_resolved32_region_tlab+136)
  at android.provider.MiuiSettings$SettingsCloudData.getCloudDataList(MiuiSettings.java:6217)
  at com.miui.server.AccessController.updateWhiteList(AccessController.java:468)
  at com.miui.server.AccessController$WorkHandler.handleMessage(AccessController.java:156)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SecurityManagerService" prio=5 tid=73 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140621c0 self=0x7216321400
  | sysTid=1906 nice=0 cgrp=default sched=0/0 handle=0x72156d54f0
  | state=S schedstat=( 14382094 27011616 306 ) utm=0 stm=1 core=6 HZ=100
  | stack=0x72155d2000-0x72155d4000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"MiuiBackup" prio=5 tid=74 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140622d8 self=0x721631a800
  | sysTid=1908 nice=10 cgrp=default sched=0/0 handle=0x72155cf4f0
  | state=S schedstat=( 16184229 142152430 305 ) utm=1 stm=0 core=7 HZ=100
  | stack=0x72154cc000-0x72154ce000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"miui.bg" prio=5 tid=75 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140623f0 self=0x721631d800
  | sysTid=1909 nice=10 cgrp=default sched=0/0 handle=0x72154c94f0
  | state=S schedstat=( 45810103 147501772 336 ) utm=2 stm=2 core=6 HZ=100
  | stack=0x72153c6000-0x72153c8000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"ProcessManager" prio=5 tid=76 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062508 self=0x7216338000
  | sysTid=1910 nice=0 cgrp=default sched=0/0 handle=0x72153c34f0
  | state=S schedstat=( 1885413736156 1133135968591 2148953 ) utm=104676 stm=83865 core=7 HZ=100
  | stack=0x72152c0000-0x72152c2000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"PowerKeeperPolicy" prio=5 tid=77 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062620 self=0x7216338c00
  | sysTid=1911 nice=0 cgrp=default sched=0/0 handle=0x72152bd4f0
  | state=S schedstat=( 192955940 957789765 2300 ) utm=7 stm=12 core=7 HZ=100
  | stack=0x72151ba000-0x72151bc000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ScreenEffectThread" prio=5 tid=78 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062738 self=0x7216339800
  | sysTid=1912 nice=0 cgrp=default sched=0/0 handle=0x72151b74f0
  | state=S schedstat=( 95137440 185337509 794 ) utm=5 stm=4 core=6 HZ=100
  | stack=0x72150b4000-0x72150b6000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"GraphicsStats-disk" prio=5 tid=79 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062850 self=0x721633a400
  | sysTid=1913 nice=10 cgrp=default sched=0/0 handle=0x72150b14f0
  | state=S schedstat=( 92611479720 620830464709 441319 ) utm=3457 stm=5804 core=6 HZ=100
  | stack=0x7214fae000-0x7214fb0000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SliceManagerService" prio=5 tid=80 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062968 self=0x721633b000
  | sysTid=1914 nice=10 cgrp=default sched=0/0 handle=0x7214fab4f0
  | state=S schedstat=( 22084067 206961713 321 ) utm=2 stm=0 core=6 HZ=100
  | stack=0x7214ea8000-0x7214eaa000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"CameraService_proxy" prio=5 tid=81 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062a80 self=0x721633bc00
  | sysTid=1915 nice=-4 cgrp=default sched=0/0 handle=0x7214ea54f0
  | state=S schedstat=( 14655838 22385313 319 ) utm=0 stm=1 core=7 HZ=100
  | stack=0x7214da2000-0x7214da4000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)

"vibrator-injector" prio=5 tid=82 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062b98 self=0x721633c800
  | sysTid=1916 nice=0 cgrp=default sched=0/0 handle=0x7214d9f4f0
  | state=S schedstat=( 35038656728 372541980497 617264 ) utm=1934 stm=1569 core=7 HZ=100
  | stack=0x7214c9c000-0x7214c9e000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-0" prio=5 tid=83 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062cb0 self=0x721633d400
  | sysTid=1917 nice=0 cgrp=default sched=0/0 handle=0x72149ff4f0
  | state=S schedstat=( 9757579429 18458137182 133005 ) utm=454 stm=521 core=7 HZ=100
  | stack=0x72148fc000-0x72148fe000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"MiuiWifiService" prio=5 tid=84 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062dc8 self=0x721c48f000
  | sysTid=1918 nice=0 cgrp=default sched=0/0 handle=0x72148f94f0
  | state=S schedstat=( 1212465240382 1112745092152 1455299 ) utm=105608 stm=15638 core=7 HZ=100
  | stack=0x72147f6000-0x72147f8000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"wifiAwareService" prio=5 tid=85 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062ee0 self=0x721c48fc00
  | sysTid=1919 nice=0 cgrp=default sched=0/0 handle=0x72147f34f0
  | state=S schedstat=( 5156637636 35136556240 67875 ) utm=259 stm=256 core=7 HZ=100
  | stack=0x72146f0000-0x72146f2000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"EthernetServiceThread" prio=5 tid=86 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14062ff8 self=0x721c490800
  | sysTid=1920 nice=0 cgrp=default sched=0/0 handle=0x72146ed4f0
  | state=S schedstat=( 5061854545 36088108736 81225 ) utm=244 stm=262 core=7 HZ=100
  | stack=0x72145ea000-0x72145ec000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"TaskSnapshotPersister" prio=5 tid=87 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063110 self=0x721c491400
  | sysTid=1923 nice=10 cgrp=default sched=0/0 handle=0x72145e74f0
  | state=S schedstat=( 7216325582565 7464012044229 4926300 ) utm=625618 stm=96014 core=5 HZ=100
  | stack=0x72144e4000-0x72144e6000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x031bc3f5> (a java.lang.Object)
  at com.android.server.wm.TaskSnapshotPersister$1.run(TaskSnapshotPersister.java:245)
  - locked <0x031bc3f5> (a java.lang.Object)

"MiuiGestureController" prio=5 tid=88 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140631c0 self=0x721c492000
  | sysTid=1924 nice=-4 cgrp=default sched=0/0 handle=0x72144e14f0
  | state=S schedstat=( 17569584505 60744368620 212926 ) utm=995 stm=761 core=6 HZ=100
  | stack=0x72143de000-0x72143e0000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"PhotonicModulator" prio=5 tid=89 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140632d8 self=0x721bc8f000
  | sysTid=1925 nice=0 cgrp=default sched=0/0 handle=0x72143db4f0
  | state=S schedstat=( 17618910012 59769892243 182670 ) utm=969 stm=792 core=5 HZ=100
  | stack=0x72142d8000-0x72142da000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x0d05458a> (a java.lang.Object)
  at com.android.server.display.DisplayPowerState$PhotonicModulator.run(DisplayPowerState.java:435)
  - locked <0x0d05458a> (a java.lang.Object)

"LazyTaskWriterThread" prio=5 tid=90 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063380 self=0x721c492c00
  | sysTid=1926 nice=10 cgrp=default sched=0/0 handle=0x72142d54f0
  | state=S schedstat=( 759453228002 3644799947182 2957016 ) utm=26033 stm=49912 core=5 HZ=100
  | stack=0x72141d2000-0x72141d4000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x092ad7fb> (a com.android.server.am.TaskPersister)
  at com.android.server.am.TaskPersister$LazyTaskWriterThread.processNextItem(TaskPersister.java:692)
  - locked <0x092ad7fb> (a com.android.server.am.TaskPersister)
  at com.android.server.am.TaskPersister$LazyTaskWriterThread.run(TaskPersister.java:665)

"SyncManager" prio=5 tid=91 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063630 self=0x721c493800
  | sysTid=1929 nice=10 cgrp=default sched=0/0 handle=0x72141cf4f0
  | state=S schedstat=( 4496004057 16738890029 16069 ) utm=255 stm=194 core=6 HZ=100
  | stack=0x72140cc000-0x72140ce000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"Binder:1471_3" prio=5 tid=92 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063748 self=0x721bc96800
  | sysTid=1938 nice=0 cgrp=default sched=0/0 handle=0x72140c94f0
  | state=S schedstat=( 5684935438093 5577583248536 12451246 ) utm=480567 stm=87926 core=6 HZ=100
  | stack=0x7213fce000-0x7213fd0000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_4" prio=5 tid=93 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140637d0 self=0x7214bd4800
  | sysTid=1939 nice=0 cgrp=default sched=0/0 handle=0x7213fcb4f0
  | state=S schedstat=( 5463796506586 5346153923200 11900549 ) utm=461864 stm=84515 core=6 HZ=100
  | stack=0x7213ed0000-0x7213ed2000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Thread-5" prio=5 tid=94 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063b58 self=0x7214bcdc00
  | sysTid=1945 nice=0 cgrp=default sched=0/0 handle=0x7213dc74f0
  | state=S schedstat=( 31805833 49058492 259 ) utm=0 stm=3 core=6 HZ=100
  | stack=0x7213cc4000-0x7213cc6000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: __skb_wait_for_more_packets+0x114/0x178
  kernel: __skb_recv_datagram+0x70/0xc4
  kernel: skb_recv_datagram+0x3c/0x5c
  kernel: unix_accept+0x98/0x164
  kernel: SyS_accept4+0x138/0x228
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e454  /system/lib64/libc.so (__accept4+4)
  native: #01 pc 0000000000001070  /system/lib64/libnetd_client.so ((anonymous namespace)::netdClientAccept4(int, sockaddr*, unsigned int*, int)+44)
  native: #02 pc 000000000002a518  /system/lib64/libjavacore.so (Linux_accept(_JNIEnv*, _jobject*, _jobject*, _jobject*)+144)
  at libcore.io.Linux.accept(Native method)
  at libcore.io.BlockGuardOs.accept(BlockGuardOs.java:59)
  at android.system.Os.accept(Os.java:41)
  at com.android.server.am.NativeCrashListener.run(NativeCrashListener.java:129)

"UsbService host thread" prio=5 tid=95 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063c10 self=0x7214bcd000
  | sysTid=1943 nice=0 cgrp=default sched=0/0 handle=0x7213ecd4f0
  | state=S schedstat=( 23285574 42320413 237 ) utm=1 stm=1 core=6 HZ=100
  | stack=0x7213dca000-0x7213dcc000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: wait_woken+0x44/0x9c
  kernel: inotify_read+0x278/0x4a4
  kernel: __vfs_read+0x38/0x12c
  kernel: vfs_read+0xcc/0x2c8
  kernel: SyS_read+0x50/0xb0
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006eff4  /system/lib64/libc.so (read+4)
  native: #01 pc 0000000000001b90  /system/lib64/libusbhost.so (usb_host_read_event+76)
  native: #02 pc 00000000000020fc  /system/lib64/libusbhost.so (usb_host_run+152)
  at com.android.server.usb.UsbHostManager.monitorUsbHostBus(Native method)
  at com.android.server.usb.UsbHostManager.lambda$XT3F5aQci4H6VWSBYBQQNSzpnvs(UsbHostManager.java:-1)
  at com.android.server.usb.-$$Lambda$UsbHostManager$XT3F5aQci4H6VWSBYBQQNSzpnvs.run(lambda:-1)
  at java.lang.Thread.run(Thread.java:764)

"NetworkStatsObservers" prio=5 tid=96 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063ce8 self=0x7214bce800
  | sysTid=1971 nice=0 cgrp=default sched=0/0 handle=0x7213cc14f0
  | state=S schedstat=( 703666163 1279543856 11448 ) utm=22 stm=48 core=6 HZ=100
  | stack=0x7213bbe000-0x7213bc0000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SoundPool" prio=5 tid=97 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063e00 self=0x72162f3000
  | sysTid=1978 nice=0 cgrp=default sched=0/0 handle=0x7213bbb4f0
  | state=S schedstat=( 14501977 6571928 199 ) utm=1 stm=0 core=6 HZ=100
  | stack=0x7213ac0000-0x7213ac2000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 000000000002248c  /system/lib64/libc.so (__futex_wait_ex(void volatile*, bool, int, bool, timespec const*)+140)
  native: #02 pc 00000000000812f0  /system/lib64/libc.so (pthread_cond_wait+60)
  native: #03 pc 00000000000064d8  /system/lib64/libsoundpool.so (android::SoundPool::run()+52)
  native: #04 pc 0000000000006494  /system/lib64/libsoundpool.so (android::SoundPool::beginThread(void*)+8)
  native: #05 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #06 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #07 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"SoundPoolThread" prio=5 tid=98 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063e88 self=0x7219dc1800
  | sysTid=1979 nice=0 cgrp=default sched=0/0 handle=0x7213abd4f0
  | state=S schedstat=( 45774224 37180883 1002 ) utm=1 stm=3 core=6 HZ=100
  | stack=0x72139c2000-0x72139c4000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 000000000002248c  /system/lib64/libc.so (__futex_wait_ex(void volatile*, bool, int, bool, timespec const*)+140)
  native: #02 pc 00000000000812f0  /system/lib64/libc.so (pthread_cond_wait+60)
  native: #03 pc 000000000000952c  /system/lib64/libsoundpool.so (android::SoundPoolThread::run()+116)
  native: #04 pc 000000000000939c  /system/lib64/libsoundpool.so (android::SoundPoolThread::beginThread(void*)+8)
  native: #05 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #06 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #07 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"watchdog" prio=5 tid=101 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063f10 self=0x7214bcf400
  | sysTid=2027 nice=0 cgrp=default sched=0/0 handle=0x72136b34f0
  | state=S schedstat=( 24336832330 7820231936 40342 ) utm=1788 stm=645 core=6 HZ=100
  | stack=0x72135b0000-0x72135b2000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e850  /system/lib64/libart.so (artAllocObjectFromCodeInitializedRegionTLAB+380)
  native: #06 pc 000000000056465c  /system/lib64/libart.so (art_quick_alloc_object_initialized_region_tlab+108)
  at java.nio.CharBuffer.wrap(CharBuffer.java:207)
  at sun.nio.cs.StreamEncoder.implWrite(StreamEncoder.java:265)
  at sun.nio.cs.StreamEncoder.write(StreamEncoder.java:125)
  - locked <0x06cb153e> (a java.io.FileWriter)
  at sun.nio.cs.StreamEncoder.write(StreamEncoder.java:113)
  at java.io.OutputStreamWriter.write(OutputStreamWriter.java:194)
  at com.android.server.Watchdog.binderStateRead(Watchdog.java:936)
  at com.android.server.Watchdog.dumpTracesFile(Watchdog.java:804)
  at com.android.server.Watchdog.run(Watchdog.java:679)

"EmergencyAffordanceService" prio=5 tid=103 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14063fd0 self=0x7214bd0000
  | sysTid=2035 nice=0 cgrp=default sched=0/0 handle=0x72111ff4f0
  | state=S schedstat=( 153810137 287581038 1441 ) utm=12 stm=3 core=7 HZ=100
  | stack=0x72110fc000-0x72110fe000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"NetworkTimeUpdateService" prio=5 tid=104 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140640e8 self=0x7214bd0c00
  | sysTid=2047 nice=0 cgrp=default sched=0/0 handle=0x72110f94f0
  | state=S schedstat=( 14577978155 28424290479 39273 ) utm=503 stm=954 core=5 HZ=100
  | stack=0x7210ff6000-0x7210ff8000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"Binder:1471_5" prio=5 tid=105 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064200 self=0x721c54d000
  | sysTid=2125 nice=0 cgrp=default sched=0/0 handle=0x7210ff34f0
  | state=S schedstat=( 5556439247071 5491524336507 12048300 ) utm=469619 stm=86024 core=6 HZ=100
  | stack=0x7210ef8000-0x7210efa000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_6" prio=5 tid=106 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064288 self=0x721bdfb000
  | sysTid=2126 nice=0 cgrp=default sched=0/0 handle=0x72107ff4f0
  | state=S schedstat=( 5605933458050 5415448290382 12052578 ) utm=475916 stm=84677 core=5 HZ=100
  | stack=0x7210704000-0x7210706000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_7" prio=5 tid=107 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064310 self=0x721a129800
  | sysTid=2166 nice=0 cgrp=default sched=0/0 handle=0x721050d4f0
  | state=S schedstat=( 5496965802960 5440511736699 11950159 ) utm=464605 stm=85091 core=6 HZ=100
  | stack=0x7210412000-0x7210414000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_8" prio=5 tid=108 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064398 self=0x7219dd9000
  | sysTid=2168 nice=0 cgrp=default sched=0/0 handle=0x720fdff4f0
  | state=S schedstat=( 5601724562758 5464273391739 12340199 ) utm=473400 stm=86772 core=6 HZ=100
  | stack=0x720fd04000-0x720fd06000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.activityPaused(ActivityManagerService.java:8527)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:225)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"MiuiActivityController" prio=5 tid=33 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064420 self=0x721bdfbc00
  | sysTid=2289 nice=-2 cgrp=default sched=0/0 handle=0x71fe4f44f0
  | state=S schedstat=( 261588736173 411088588994 2174454 ) utm=15383 stm=10775 core=5 HZ=100
  | stack=0x71fe3f1000-0x71fe3f3000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"BluetoothRouteManager" prio=5 tid=110 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064538 self=0x721274bc00
  | sysTid=2311 nice=0 cgrp=default sched=0/0 handle=0x71fd6964f0
  | state=S schedstat=( 38071623 67992183 408 ) utm=3 stm=0 core=7 HZ=100
  | stack=0x71fd593000-0x71fd595000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"AudioPortEventHandler" prio=5 tid=111 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064650 self=0x721274c800
  | sysTid=2312 nice=0 cgrp=default sched=0/0 handle=0x71fd5904f0
  | state=S schedstat=( 12090584697 18868572887 133185 ) utm=682 stm=527 core=5 HZ=100
  | stack=0x71fd48d000-0x71fd48f000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"MissedCallNotifier" prio=5 tid=112 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064768 self=0x721274d400
  | sysTid=2318 nice=0 cgrp=default sched=0/0 handle=0x71fd46a4f0
  | state=S schedstat=( 15394174 41631247 307 ) utm=0 stm=1 core=5 HZ=100
  | stack=0x71fd367000-0x71fd369000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"com.android.server.telecom.CallAudioRouteStateMachine" prio=5 tid=113 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064880 self=0x720bb10000
  | sysTid=2320 nice=0 cgrp=default sched=0/0 handle=0x71fd3644f0
  | state=S schedstat=( 6335597097 9400574657 31123 ) utm=399 stm=234 core=5 HZ=100
  | stack=0x71fd261000-0x71fd263000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"VoiceReporter" prio=5 tid=114 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064998 self=0x720bb10c00
  | sysTid=2327 nice=0 cgrp=default sched=0/0 handle=0x71fd2524f0
  | state=S schedstat=( 13740847 27794320 306 ) utm=0 stm=1 core=7 HZ=100
  | stack=0x71fd14f000-0x71fd151000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"RingerFlashManager" prio=5 tid=115 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064ab0 self=0x720bb11800
  | sysTid=2328 nice=0 cgrp=default sched=0/0 handle=0x71fd1404f0
  | state=S schedstat=( 13084323 42903025 314 ) utm=0 stm=1 core=5 HZ=100
  | stack=0x71fd03d000-0x71fd03f000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"CallAudioModeStateMachine" prio=5 tid=116 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064bc8 self=0x720bb12400
  | sysTid=2333 nice=0 cgrp=default sched=0/0 handle=0x71fd02e4f0
  | state=S schedstat=( 19514883740 51582344148 140038 ) utm=795 stm=1156 core=7 HZ=100
  | stack=0x71fcf2b000-0x71fcf2d000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"queued-work-looper" prio=5 tid=119 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064ce0 self=0x720eeef000
  | sysTid=2415 nice=-2 cgrp=default sched=0/0 handle=0x71fb6394f0
  | state=S schedstat=( 14163329 28059375 307 ) utm=1 stm=0 core=5 HZ=100
  | stack=0x71fb536000-0x71fb538000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"backup" prio=5 tid=102 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064df8 self=0x7232bb5800
  | sysTid=2758 nice=10 cgrp=default sched=0/0 handle=0x71faf4f4f0
  | state=S schedstat=( 19821787206 238385429078 282947 ) utm=1087 stm=895 core=7 HZ=100
  | stack=0x71fae4c000-0x71fae4e000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"Binder:1471_9" prio=5 tid=118 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064f10 self=0x7232238800
  | sysTid=2893 nice=0 cgrp=default sched=0/0 handle=0x71fae494f0
  | state=S schedstat=( 5799213724493 5638656392007 12435847 ) utm=490632 stm=89289 core=6 HZ=100
  | stack=0x71fad4e000-0x71fad50000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.checkContentProviderAccess(ActivityManagerService.java:12359)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.am.ActivityManagerService$LocalService.checkContentProviderAccess(ActivityManagerService.java:27217)
  at com.android.server.content.ContentService.notifyChange(ContentService.java:404)
  at android.content.IContentService$Stub.onTransact(IContentService.java:100)
  at com.android.server.content.ContentService.onTransact(ContentService.java:262)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_A" prio=5 tid=120 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140656f8 self=0x7219cc1000
  | sysTid=2894 nice=0 cgrp=default sched=0/0 handle=0x71f8f5a4f0
  | state=S schedstat=( 5606271128784 5440056263442 12089170 ) utm=475455 stm=85172 core=7 HZ=100
  | stack=0x71f8e5f000-0x71f8e61000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012ef34  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_enforceInterface(_JNIEnv*, _jclass*, long, _jstring*)+76)
  at android.os.Parcel.nativeEnforceInterface(Native method)
  at android.os.Parcel.enforceInterface(Parcel.java:613)
  at android.net.metrics.INetdEventListener$Stub.onTransact(INetdEventListener.java:89)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_B" prio=5 tid=121 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065780 self=0x72162ba000
  | sysTid=2931 nice=0 cgrp=default sched=0/0 handle=0x71f8e5c4f0
  | state=S schedstat=( 5704334149540 5498497928663 12397437 ) utm=483158 stm=87275 core=6 HZ=100
  | stack=0x71f8d61000-0x71f8d63000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_C" prio=5 tid=122 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065808 self=0x7215e8d400
  | sysTid=2941 nice=0 cgrp=default sched=0/0 handle=0x71f8d5e4f0
  | state=S schedstat=( 5664155065063 5531943872444 12255267 ) utm=481354 stm=85061 core=5 HZ=100
  | stack=0x71f8c63000-0x71f8c65000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_D" prio=5 tid=123 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065890 self=0x721273ec00
  | sysTid=2949 nice=0 cgrp=default sched=0/0 handle=0x71f8c604f0
  | state=S schedstat=( 5699368207758 5529397103753 12255303 ) utm=483105 stm=86831 core=7 HZ=100
  | stack=0x71f8b65000-0x71f8b67000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.content.pm.PackageInfo.writeToParcel(PackageInfo.java:430)
  at android.content.pm.IPackageManager$Stub.onTransact(IPackageManager.java:88)
  at com.android.server.pm.PackageManagerService.onTransact(PackageManagerService.java:4014)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_E" prio=5 tid=124 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065918 self=0x7219cc0400
  | sysTid=2950 nice=0 cgrp=default sched=0/0 handle=0x71f8b624f0
  | state=S schedstat=( 5637096758827 5461157030467 12076283 ) utm=479026 stm=84683 core=7 HZ=100
  | stack=0x71f8a67000-0x71f8a69000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_F" prio=5 tid=125 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140659a0 self=0x721d2ce800
  | sysTid=2981 nice=0 cgrp=default sched=0/0 handle=0x71f8a644f0
  | state=S schedstat=( 5673743693733 5620522491737 12384096 ) utm=479343 stm=88031 core=5 HZ=100
  | stack=0x71f8969000-0x71f896b000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_10" prio=5 tid=126 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065a28 self=0x7219d0fc00
  | sysTid=2982 nice=0 cgrp=default sched=0/0 handle=0x71f89664f0
  | state=S schedstat=( 5689502913089 5566377938919 12255368 ) utm=482083 stm=86867 core=5 HZ=100
  | stack=0x71f886b000-0x71f886d000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_11" prio=5 tid=127 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065c60 self=0x720b025000
  | sysTid=3089 nice=0 cgrp=default sched=0/0 handle=0x71f88684f0
  | state=S schedstat=( 5673202371471 5511902315320 12455377 ) utm=478706 stm=88614 core=7 HZ=100
  | stack=0x71f876d000-0x71f876f000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_12" prio=5 tid=128 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065e70 self=0x7219d29400
  | sysTid=3094 nice=0 cgrp=default sched=0/0 handle=0x71f876a4f0
  | state=S schedstat=( 5665001237123 5524648527997 12279231 ) utm=480224 stm=86276 core=6 HZ=100
  | stack=0x71f866f000-0x71f8671000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_13" prio=5 tid=129 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14065ef8 self=0x720b02f800
  | sysTid=3095 nice=0 cgrp=default sched=0/0 handle=0x71f866c4f0
  | state=S schedstat=( 5750460285253 5504208254870 12403171 ) utm=486558 stm=88488 core=3 HZ=100
  | stack=0x71f8571000-0x71f8573000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_14" prio=5 tid=130 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140662d8 self=0x7219279c00
  | sysTid=3109 nice=0 cgrp=default sched=0/0 handle=0x71f856e4f0
  | state=S schedstat=( 5716387062215 5522030278621 12221383 ) utm=484961 stm=86677 core=5 HZ=100
  | stack=0x71f8473000-0x71f8475000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.unbindService(ActivityManagerService.java:21157)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:462)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_15" prio=5 tid=131 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14066360 self=0x720c44d000
  | sysTid=3112 nice=0 cgrp=default sched=0/0 handle=0x71f84704f0
  | state=S schedstat=( 5826599026453 5652476473159 12489512 ) utm=494284 stm=88375 core=5 HZ=100
  | stack=0x71f8375000-0x71f8377000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_16" prio=5 tid=132 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140664e0 self=0x7219282400
  | sysTid=3133 nice=0 cgrp=default sched=0/0 handle=0x71f83724f0
  | state=S schedstat=( 5835016458624 5519951925054 12306432 ) utm=495486 stm=88015 core=6 HZ=100
  | stack=0x71f8277000-0x71f8279000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.refContentProvider(ActivityManagerService.java:13277)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:389)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_17" prio=5 tid=133 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14066568 self=0x720c454800
  | sysTid=3135 nice=0 cgrp=default sched=0/0 handle=0x71f82744f0
  | state=S schedstat=( 6031064883422 5731801997441 12785764 ) utm=512431 stm=90675 core=7 HZ=100
  | stack=0x71f8179000-0x71f817b000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_18" prio=5 tid=134 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140665f0 self=0x721929cc00
  | sysTid=3140 nice=0 cgrp=default sched=0/0 handle=0x71f81764f0
  | state=S schedstat=( 5787714269398 5563231442725 12420282 ) utm=489680 stm=89091 core=7 HZ=100
  | stack=0x71f807b000-0x71f807d000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.content.ComponentName.writeToParcel(ComponentName.java:329)
  at android.content.ComponentName.writeToParcel(ComponentName.java:343)
  at android.app.ActivityManager$RunningTaskInfo.writeToParcel(ActivityManager.java:1804)
  at android.os.Parcel.writeTypedObject(Parcel.java:1519)
  at android.os.Parcel.writeTypedList(Parcel.java:1398)
  at android.os.Parcel.writeTypedList(Parcel.java:1383)
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:291)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_19" prio=5 tid=135 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14066678 self=0x720eb42000
  | sysTid=3142 nice=0 cgrp=default sched=0/0 handle=0x71f80784f0
  | state=S schedstat=( 6074256359605 5673915494670 12730181 ) utm=514839 stm=92586 core=7 HZ=100
  | stack=0x71f7f7d000-0x71f7f7f000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.view.DisplayInfo.writeToParcel(DisplayInfo.java:425)
  at android.hardware.display.IDisplayManager$Stub.onTransact(IDisplayManager.java:56)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_1A" prio=5 tid=136 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14066848 self=0x72192a8400
  | sysTid=3143 nice=0 cgrp=default sched=0/0 handle=0x71f7f7a4f0
  | state=S schedstat=( 5932810422177 5710674901204 12590225 ) utm=504411 stm=88870 core=6 HZ=100
  | stack=0x71f7e7f000-0x71f7e81000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.unregisterReceiver(ActivityManagerService.java:21636)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:162)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"RenderThread" daemon prio=7 tid=137 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140669b0 self=0x7232237000
  | sysTid=3860 nice=10 cgrp=default sched=0/0 handle=0x720fbfb4f0
  | state=S schedstat=( 3232352589816 6707959899416 4346644 ) utm=142286 stm=180949 core=5 HZ=100
  | stack=0x720fb00000-0x720fb02000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 0000000000115808  /system/lib64/libhwui.so (android::uirenderer::renderthread::RenderThread::threadLoop()+492)
  native: #04 pc 000000000000faf4  /system/lib64/libutils.so (android::Thread::_threadLoop(void*)+280)
  native: #05 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #06 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"AsyncQueryWorker" prio=5 tid=139 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14066a38 self=0x721a0be400
  | sysTid=4008 nice=0 cgrp=default sched=0/0 handle=0x720f9f74f0
  | state=S schedstat=( 7113302592 17163659866 49072 ) utm=411 stm=300 core=5 HZ=100
  | stack=0x720f8f4000-0x720f8f6000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"HwBinder:1471_4" prio=5 tid=12 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14066b50 self=0x7219d25800
  | sysTid=8981 nice=0 cgrp=default sched=0/0 handle=0x72139bf4f0
  | state=S schedstat=( 49813089978 82605069911 324223 ) utm=3297 stm=1684 core=6 HZ=100
  | stack=0x72138c4000-0x72138c6000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 00000000003841b4  /system/lib64/libart.so (art::JNI::GetPrimitiveArrayCritical(_JNIEnv*, _jarray*, unsigned char*)+748)
  native: #04 pc 000000000005d1e8  /system/lib64/libandroid_servers.so (android::android_location_GnssLocationProvider_read_nmea(_JNIEnv*, _jobject*, _jbyteArray*, int)+44)
  at com.android.server.location.GnssLocationProvider.native_read_nmea(Native method)
  at com.android.server.location.GnssLocationProvider.reportNmea(GnssLocationProvider.java:1922)

"HwBinder:1471_5" prio=5 tid=34 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x140b2bd0 self=0x7216637400
  | sysTid=9688 nice=0 cgrp=default sched=0/0 handle=0x720fd014f0
  | state=S schedstat=( 53497960714 90546042230 351864 ) utm=3535 stm=1814 core=7 HZ=100
  | stack=0x720fc06000-0x720fc08000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000013dcd4  /system/lib64/libart.so (art::mirror::Object* art::gc::Heap::AllocObjectWithAllocator<true, false, art::VoidFunctor>(art::Thread*, art::ObjPtr<art::gc::Heap::AllocObjectWithAllocator<true, false, art::VoidFunctor>::Class>, unsigned long, art::gc::AllocatorType, art::VoidFunctor const&)+876)
  native: #06 pc 0000000000331840  /system/lib64/libart.so (art::JNI::NewObjectV(_JNIEnv*, _jclass*, _jmethodID*, std::__va_list)+696)
  native: #07 pc 00000000000c4fd0  /system/lib64/libandroid_runtime.so (_JNIEnv::NewObject(_jclass*, _jmethodID*, ...)+120)
  native: #08 pc 0000000000126b80  /system/lib64/libandroid_runtime.so (android::JHwParcel::NewObject(_JNIEnv*)+108)
  native: #09 pc 00000000001216d0  /system/lib64/libandroid_runtime.so (android::JHwBinder::onTransact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+80)
  native: #10 pc 000000000001df34  /system/lib64/libhwbinder.so (android::hardware::BHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+72)
  native: #11 pc 000000000001508c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::executeCommand(int)+1508)
  native: #12 pc 0000000000014938  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::getAndExecuteCommand()+204)
  native: #13 pc 0000000000015708  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::joinThreadPool(bool)+268)
  native: #14 pc 000000000001d530  /system/lib64/libhwbinder.so (android::hardware::PoolThread::threadLoop()+24)
  native: #15 pc 000000000000faf4  /system/lib64/libutils.so (android::Thread::_threadLoop(void*)+280)
  native: #16 pc 00000000000c23e0  /system/lib64/libandroid_runtime.so (android::AndroidRuntime::javaThreadShell(void*)+140)
  native: #17 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #18 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
  (no managed stack frames)

"Okio Watchdog" daemon prio=5 tid=138 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146720 self=0x7215f60400
  | sysTid=11653 nice=0 cgrp=default sched=0/0 handle=0x720d4f14f0
  | state=S schedstat=( 1139362801 3975512042 16677 ) utm=54 stm=59 core=5 HZ=100
  | stack=0x720d3ee000-0x720d3f0000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x0e7a3056> (a java.lang.Class<com.android.okhttp.okio.AsyncTimeout>)
  at com.android.okhttp.okio.AsyncTimeout.awaitTimeout(AsyncTimeout.java:311)
  - locked <0x0e7a3056> (a java.lang.Class<com.android.okhttp.okio.AsyncTimeout>)
  at com.android.okhttp.okio.AsyncTimeout.access$000(AsyncTimeout.java:40)
  at com.android.okhttp.okio.AsyncTimeout$Watchdog.run(AsyncTimeout.java:286)

"Binder:1471_1B" prio=5 tid=140 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141467a8 self=0x720c44e800
  | sysTid=12233 nice=0 cgrp=default sched=0/0 handle=0x720d3eb4f0
  | state=S schedstat=( 5953471358862 5772903159270 12843016 ) utm=504264 stm=91083 core=5 HZ=100
  | stack=0x720d2f0000-0x720d2f2000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"tonegenerator-dtmf" prio=5 tid=143 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146830 self=0x721d31b000
  | sysTid=17519 nice=0 cgrp=default sched=0/0 handle=0x720fafd4f0
  | state=S schedstat=( 2415105797 4662364622 22892 ) utm=99 stm=142 core=7 HZ=100
  | stack=0x720f9fa000-0x720f9fc000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"pool-1-thread-1" prio=5 tid=142 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146948 self=0x7215e8c800
  | sysTid=19493 nice=0 cgrp=default sched=0/0 handle=0x720e5234f0
  | state=S schedstat=( 13726611713 68447787955 177309 ) utm=657 stm=715 core=5 HZ=100
  | stack=0x720e420000-0x720e422000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x01a14700> (a java.lang.Object)
  at java.lang.Thread.parkFor$(Thread.java:2137)
  - locked <0x01a14700> (a java.lang.Object)
  at sun.misc.Unsafe.park(Unsafe.java:358)
  at java.util.concurrent.locks.LockSupport.park(LockSupport.java:190)
  at java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject.await(AbstractQueuedSynchronizer.java:2059)
  at java.util.concurrent.LinkedBlockingQueue.take(LinkedBlockingQueue.java:442)
  at java.util.concurrent.ThreadPoolExecutor.getTask(ThreadPoolExecutor.java:1092)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1152)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)

"Binder:1471_1C" prio=5 tid=117 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146ad0 self=0x720bb80c00
  | sysTid=30811 nice=-10 cgrp=default sched=0/0 handle=0x72107014f0
  | state=S schedstat=( 6235261913599 5972957584608 13178411 ) utm=528424 stm=95102 core=6 HZ=100
  | stack=0x7210606000-0x7210608000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.isInMultiWindowMode(ActivityManagerService.java:9172)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:2841)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_1D" prio=5 tid=141 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146bc0 self=0x720b054800
  | sysTid=31457 nice=0 cgrp=default sched=0/0 handle=0x720e41d4f0
  | state=S schedstat=( 6171761498634 5922434673735 13155658 ) utm=522123 stm=95053 core=5 HZ=100
  | stack=0x720e322000-0x720e324000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_1E" prio=5 tid=144 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146dd0 self=0x720c474000
  | sysTid=31458 nice=0 cgrp=default sched=0/0 handle=0x720d5f74f0
  | state=S schedstat=( 6073054990763 5873032967856 12943936 ) utm=513683 stm=93622 core=5 HZ=100
  | stack=0x720d4fc000-0x720d4fe000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_1F" prio=5 tid=145 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14146fa0 self=0x7232a14c00
  | sysTid=16657 nice=0 cgrp=default sched=0/0 handle=0x72137b94f0
  | state=S schedstat=( 6044208937351 5823894789935 13033007 ) utm=511540 stm=92880 core=5 HZ=100
  | stack=0x72136be000-0x72136c0000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)

"Binder:1471_20" prio=5 tid=146 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147028 self=0x72126b5800
  | sysTid=18045 nice=-2 cgrp=default sched=0/0 handle=0x72049824f0
  | state=S schedstat=( 6101767900274 5905637387083 13051781 ) utm=516502 stm=93674 core=7 HZ=100
  | stack=0x7204887000-0x7204889000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.content.pm.PackageItemInfo.writeToParcel(PackageItemInfo.java:652)
  at android.content.pm.ApplicationInfo.writeToParcel(ApplicationInfo.java:1513)
  at android.app.IApplicationThread$Stub$Proxy.bindApplication(IApplicationThread.java:943)
  at com.android.server.am.ActivityManagerService.attachApplicationLocked(ActivityManagerService.java:8146)
  at com.android.server.am.ActivityManagerService.attachApplication(ActivityManagerService.java:8255)
  - locked <0x00c6c1f5> (a com.android.server.am.ActivityManagerService)
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:199)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)

"pool-2-thread-1" prio=5 tid=150 Waiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141470b0 self=0x721a126800
  | sysTid=19560 nice=0 cgrp=default sched=0/0 handle=0x720366e4f0
  | state=S schedstat=( 33822422861 130814166658 349240 ) utm=1903 stm=1479 core=5 HZ=100
  | stack=0x720356b000-0x720356d000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x0ed88f2f> (a java.lang.Object)
  at java.lang.Thread.parkFor$(Thread.java:2137)
  - locked <0x0ed88f2f> (a java.lang.Object)
  at sun.misc.Unsafe.park(Unsafe.java:358)
  at java.util.concurrent.locks.LockSupport.park(LockSupport.java:190)
  at java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject.await(AbstractQueuedSynchronizer.java:2059)
  at java.util.concurrent.LinkedBlockingQueue.take(LinkedBlockingQueue.java:442)
  at java.util.concurrent.ThreadPoolExecutor.getTask(ThreadPoolExecutor.java:1092)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1152)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)

"SyncHandler-1" prio=5 tid=148 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147238 self=0x7232ad4800
  | sysTid=16601 nice=0 cgrp=default sched=0/0 handle=0x72039ee4f0
  | state=S schedstat=( 11540616797 21112366999 155733 ) utm=519 stm=635 core=7 HZ=100
  | stack=0x72038eb000-0x72038ed000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-2" prio=5 tid=109 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147350 self=0x721bc95000
  | sysTid=22046 nice=0 cgrp=default sched=0/0 handle=0x720d2ed4f0
  | state=S schedstat=( 10702160733 21702154383 119833 ) utm=504 stm=566 core=5 HZ=100
  | stack=0x720d1ea000-0x720d1ec000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-3" prio=5 tid=147 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147468 self=0x7232a3ac00
  | sysTid=23431 nice=0 cgrp=default sched=0/0 handle=0x72037da4f0
  | state=S schedstat=( 13480476843 22948749829 181546 ) utm=629 stm=719 core=5 HZ=100
  | stack=0x72036d7000-0x72036d9000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-4" prio=5 tid=29 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147580 self=0x720bb1f800
  | sysTid=25840 nice=0 cgrp=default sched=0/0 handle=0x7203b864f0
  | state=S schedstat=( 11415132135 20483340818 126269 ) utm=505 stm=636 core=7 HZ=100
  | stack=0x7203a83000-0x7203a85000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-5" prio=5 tid=152 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147698 self=0x72113e8400
  | sysTid=19649 nice=0 cgrp=default sched=0/0 handle=0x720e9004f0
  | state=S schedstat=( 10965024105 22389320374 121903 ) utm=509 stm=587 core=5 HZ=100
  | stack=0x720e7fd000-0x720e7ff000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-6" prio=5 tid=153 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141477b0 self=0x721c53d400
  | sysTid=11697 nice=0 cgrp=default sched=0/0 handle=0x72035684f0
  | state=S schedstat=( 8387638335 16850275851 93129 ) utm=386 stm=452 core=7 HZ=100
  | stack=0x7203465000-0x7203467000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-7" prio=5 tid=154 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141478c8 self=0x7232a3b800
  | sysTid=11700 nice=0 cgrp=default sched=0/0 handle=0x71ff0b84f0
  | state=S schedstat=( 7569373624 15693171053 84350 ) utm=347 stm=409 core=5 HZ=100
  | stack=0x71fefb5000-0x71fefb7000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-8" prio=5 tid=99 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141479e0 self=0x7213041000
  | sysTid=11801 nice=0 cgrp=default sched=0/0 handle=0x720e7fa4f0
  | state=S schedstat=( 6196264912 12548198301 67650 ) utm=291 stm=328 core=7 HZ=100
  | stack=0x720e6f7000-0x720e6f9000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-9" prio=5 tid=100 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147af8 self=0x7232ad9000
  | sysTid=18922 nice=0 cgrp=default sched=0/0 handle=0x72038e84f0
  | state=S schedstat=( 7077102789 14285122335 78467 ) utm=343 stm=364 core=5 HZ=100
  | stack=0x72037e5000-0x72037e7000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-10" prio=5 tid=157 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147c10 self=0x7213132800
  | sysTid=24823 nice=0 cgrp=default sched=0/0 handle=0x71fe2de4f0
  | state=S schedstat=( 6750890367 14088236515 75911 ) utm=275 stm=400 core=7 HZ=100
  | stack=0x71fe1db000-0x71fe1dd000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-11" prio=5 tid=158 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147d28 self=0x721c53b000
  | sysTid=24824 nice=0 cgrp=default sched=0/0 handle=0x71fe1d84f0
  | state=S schedstat=( 5315043202 12014370959 58629 ) utm=235 stm=296 core=5 HZ=100
  | stack=0x71fe0d5000-0x71fe0d7000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-12" prio=5 tid=159 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147e40 self=0x7219cc5800
  | sysTid=24825 nice=0 cgrp=default sched=0/0 handle=0x71fd79c4f0
  | state=S schedstat=( 8589579556 16911379421 96899 ) utm=392 stm=466 core=7 HZ=100
  | stack=0x71fd699000-0x71fd69b000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-13" prio=5 tid=151 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147f58 self=0x721a05a800
  | sysTid=3466 nice=0 cgrp=default sched=0/0 handle=0x72034624f0
  | state=S schedstat=( 6703203168 14119496288 76442 ) utm=269 stm=401 core=5 HZ=100
  | stack=0x720335f000-0x7203361000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-14" prio=5 tid=155 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148070 self=0x721bc42000
  | sysTid=3467 nice=0 cgrp=default sched=0/0 handle=0x720335c4f0
  | state=S schedstat=( 5113624349 8918024149 70613 ) utm=253 stm=258 core=5 HZ=100
  | stack=0x7203259000-0x720325b000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-15" prio=5 tid=156 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148188 self=0x72130f9c00
  | sysTid=3468 nice=0 cgrp=default sched=0/0 handle=0x71fedfa4f0
  | state=S schedstat=( 6334592928 12425413655 70280 ) utm=290 stm=343 core=7 HZ=100
  | stack=0x71fecf7000-0x71fecf9000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-16" prio=5 tid=160 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141482a0 self=0x722b7aa000
  | sysTid=3471 nice=0 cgrp=default sched=0/0 handle=0x71fec0f4f0
  | state=S schedstat=( 8189544417 17971230813 95725 ) utm=365 stm=453 core=7 HZ=100
  | stack=0x71feb0c000-0x71feb0e000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-17" prio=5 tid=161 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141483b8 self=0x7211c38c00
  | sysTid=3473 nice=0 cgrp=default sched=0/0 handle=0x71fe3e44f0
  | state=S schedstat=( 2634940766 5018075988 30345 ) utm=121 stm=142 core=5 HZ=100
  | stack=0x71fe2e1000-0x71fe2e3000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-18" prio=5 tid=162 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141484d0 self=0x721a1a8c00
  | sysTid=3476 nice=0 cgrp=default sched=0/0 handle=0x71fcf1e4f0
  | state=S schedstat=( 4058573961 8458431739 44843 ) utm=193 stm=212 core=5 HZ=100
  | stack=0x71fce1b000-0x71fce1d000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-19" prio=5 tid=163 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141485e8 self=0x720ef9b400
  | sysTid=3483 nice=0 cgrp=default sched=0/0 handle=0x71fcb6e4f0
  | state=S schedstat=( 2708062721 6585826917 31003 ) utm=106 stm=164 core=7 HZ=100
  | stack=0x71fca6b000-0x71fca6d000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-20" prio=5 tid=164 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148700 self=0x7216272800
  | sysTid=31754 nice=0 cgrp=default sched=0/0 handle=0x71fb1294f0
  | state=S schedstat=( 4457080496 10069926009 52313 ) utm=215 stm=230 core=5 HZ=100
  | stack=0x71fb026000-0x71fb028000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-21" prio=5 tid=168 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148818 self=0x721bc43800
  | sysTid=31755 nice=0 cgrp=default sched=0/0 handle=0x71f7e7c4f0
  | state=S schedstat=( 3058829947 6302846238 33840 ) utm=142 stm=163 core=7 HZ=100
  | stack=0x71f7d79000-0x71f7d7b000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-22" prio=5 tid=169 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148930 self=0x721c53bc00
  | sysTid=31756 nice=0 cgrp=default sched=0/0 handle=0x71f7d564f0
  | state=S schedstat=( 3409568473 7021314449 38138 ) utm=162 stm=178 core=5 HZ=100
  | stack=0x71f7c53000-0x71f7c55000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-23" prio=5 tid=167 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148a48 self=0x7219dc2400
  | sysTid=9928 nice=0 cgrp=default sched=0/0 handle=0x71ef8bb4f0
  | state=S schedstat=( 3929583762 7641115661 43165 ) utm=175 stm=217 core=5 HZ=100
  | stack=0x71ef7b8000-0x71ef7ba000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-24" prio=5 tid=171 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148b60 self=0x721bdfc800
  | sysTid=10106 nice=0 cgrp=default sched=0/0 handle=0x71ef63d4f0
  | state=S schedstat=( 3181839123 7025652549 36202 ) utm=131 stm=187 core=7 HZ=100
  | stack=0x71ef53a000-0x71ef53c000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-25" prio=5 tid=173 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148c78 self=0x7214a53000
  | sysTid=22235 nice=0 cgrp=default sched=0/0 handle=0x71f3d054f0
  | state=S schedstat=( 3367565913 6270432386 37581 ) utm=145 stm=191 core=5 HZ=100
  | stack=0x71f3c02000-0x71f3c04000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-26" prio=5 tid=172 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148d90 self=0x721d2cf400
  | sysTid=8394 nice=0 cgrp=default sched=0/0 handle=0x7200fa14f0
  | state=S schedstat=( 2340415490 4926805534 26428 ) utm=105 stm=129 core=7 HZ=100
  | stack=0x7200e9e000-0x7200ea0000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-27" prio=5 tid=175 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148ea8 self=0x721c494400
  | sysTid=18683 nice=0 cgrp=default sched=0/0 handle=0x7200b1e4f0
  | state=S schedstat=( 2044114306 3887396455 23258 ) utm=93 stm=111 core=5 HZ=100
  | stack=0x7200a1b000-0x7200a1d000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-28" prio=5 tid=166 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14148fc0 self=0x720ea68800
  | sysTid=29755 nice=0 cgrp=default sched=0/0 handle=0x7200a184f0
  | state=S schedstat=( 2113615699 4879704480 24966 ) utm=108 stm=103 core=7 HZ=100
  | stack=0x7200915000-0x7200917000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-29" prio=5 tid=174 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141490d8 self=0x721bdfd400
  | sysTid=29759 nice=0 cgrp=default sched=0/0 handle=0x72005764f0
  | state=S schedstat=( 2532329299 5564944857 29935 ) utm=89 stm=164 core=5 HZ=100
  | stack=0x7200473000-0x7200475000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"SyncHandler-30" prio=5 tid=165 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141491f0 self=0x721d365400
  | sysTid=24048 nice=0 cgrp=default sched=0/0 handle=0x720cb934f0
  | state=S schedstat=( 973908714 2106222106 14101 ) utm=45 stm=52 core=5 HZ=100
  | stack=0x720ca90000-0x720ca92000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"ContactsAsyncWorker" prio=5 tid=181 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14149308 self=0x720ff54c00
  | sysTid=17617 nice=0 cgrp=default sched=0/0 handle=0x71c27044f0
  | state=S schedstat=( 56465897 116774887 422 ) utm=3 stm=2 core=7 HZ=100
  | stack=0x71c2601000-0x71c2603000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: SyS_epoll_wait+0x314/0x408
  kernel: SyS_epoll_pwait+0x138/0x154
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e4d0  /system/lib64/libc.so (__epoll_pwait+8)
  native: #01 pc 00000000000140b8  /system/lib64/libutils.so (android::Looper::pollInner(int)+304)
  native: #02 pc 0000000000013eec  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+60)
  native: #03 pc 000000000012d9bc  /system/lib64/libandroid_runtime.so (android::android_os_MessageQueue_nativePollOnce(_JNIEnv*, _jobject*, long, int)+44)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"Timer-20" prio=5 tid=170 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14149420 self=0x7212512400
  | sysTid=22853 nice=0 cgrp=default sched=0/0 handle=0x709b11a4f0
  | state=S schedstat=( 4793435 8482083 8 ) utm=0 stm=0 core=7 HZ=100
  | stack=0x709b017000-0x709b019000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e850  /system/lib64/libart.so (artAllocObjectFromCodeInitializedRegionTLAB+380)
  native: #06 pc 000000000056465c  /system/lib64/libart.so (art_quick_alloc_object_initialized_region_tlab+108)
  at java.lang.Integer.valueOf(Integer.java:867)
  at android.content.res.MiuiResourcesImpl.getThemeInt(MiuiResourcesImpl.java:414)
  at android.content.res.MiuiResourcesImpl.resolveOverlayValue(MiuiResourcesImpl.java:114)
  at android.content.res.MiuiResourcesImpl.getValue(MiuiResourcesImpl.java:95)
  at android.content.res.Resources.getBoolean(Resources.java:1082)
  at android.telephony.TelephonyManager.isVoiceCapable(TelephonyManager.java:4353)
  at android.telephony.TelephonyManager.getPhoneType(TelephonyManager.java:1583)
  at com.android.server.location.ComprehensiveCountryDetector.isNetworkCountryCodeAvailable(ComprehensiveCountryDetector.java:213)
  at com.android.server.location.ComprehensiveCountryDetector.getNetworkBasedCountry(ComprehensiveCountryDetector.java:223)
  at com.android.server.location.ComprehensiveCountryDetector.getCountry(ComprehensiveCountryDetector.java:170)
  at com.android.server.location.ComprehensiveCountryDetector.detectCountry(ComprehensiveCountryDetector.java:271)
  at com.android.server.location.ComprehensiveCountryDetector.access$100(ComprehensiveCountryDetector.java:58)
  at com.android.server.location.ComprehensiveCountryDetector$3.run(ComprehensiveCountryDetector.java:420)
  at java.util.TimerThread.mainLoop(Timer.java:562)
  at java.util.TimerThread.run(Timer.java:512)

"IpClient.wlan0" prio=5 tid=176 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x141494e8 self=0x7219280000
  | sysTid=22960 nice=0 cgrp=default sched=0/0 handle=0x709b0144f0
  | state=S schedstat=( 410875447 496008222 1013 ) utm=35 stm=6 core=6 HZ=100
  | stack=0x709af11000-0x709af13000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e850  /system/lib64/libart.so (artAllocObjectFromCodeInitializedRegionTLAB+380)
  native: #06 pc 000000000056465c  /system/lib64/libart.so (art_quick_alloc_object_initialized_region_tlab+108)
  at android.net.util.ConnectivityPacketSummary.summarize(ConnectivityPacketSummary.java:58)
  at android.net.ip.ConnectivityPacketTracker$PacketListener.handlePacket(ConnectivityPacketTracker.java:117)
  at android.net.util.PacketReader.handleInput(PacketReader.java:229)
  at android.net.util.PacketReader.access$100(PacketReader.java:70)
  at android.net.util.PacketReader$1.onFileDescriptorEvents(PacketReader.java:189)
  at android.os.MessageQueue.dispatchEvents(MessageQueue.java:288)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:332)
  at android.os.Looper.loop(Looper.java:168)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"NetworkMonitorNetworkAgentInfo [WIFI () - 950]" prio=5 tid=149 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14149600 self=0x72130f9000
  | sysTid=12630 nice=0 cgrp=default sched=0/0 handle=0x709af0e4f0
  | state=S schedstat=( 40175108 34431508 128 ) utm=2 stm=2 core=5 HZ=100
  | stack=0x709ae0b000-0x709ae0d000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.broadcastIntent(ActivityManagerService.java:22705)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.ContextImpl.sendBroadcastAsUser(ContextImpl.java:1234)
  at android.app.ContextImpl.sendBroadcastAsUser(ContextImpl.java:1206)
  at com.android.server.connectivity.NetworkMonitor.sendNetworkConditionsBroadcast(NetworkMonitor.java:1355)
  at com.android.server.connectivity.NetworkMonitor.isCaptivePortal(NetworkMonitor.java:1038)
  at com.android.server.connectivity.NetworkMonitor$EvaluatingState.processMessage(NetworkMonitor.java:636)
  at com.android.internal.util.StateMachine$SmHandler.processMsg(StateMachine.java:992)
  at com.android.internal.util.StateMachine$SmHandler.handleMessage(StateMachine.java:809)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)

"Thread-92297" prio=5 tid=177 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14149718 self=0x7212b9d800
  | sysTid=12635 nice=0 cgrp=default sched=0/0 handle=0x708104d4f0
  | state=S schedstat=( 1017241 316145 7 ) utm=0 stm=0 core=5 HZ=100
  | stack=0x7080f4a000-0x7080f4c000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: __skb_wait_for_more_packets+0x114/0x178
  kernel: __skb_recv_datagram+0x70/0xc4
  kernel: skb_recv_datagram+0x3c/0x5c
  kernel: packet_recvmsg+0x6c/0x308
  kernel: sock_read_iter+0xc8/0xf4
  kernel: __vfs_read+0xe8/0x12c
  kernel: vfs_read+0xcc/0x2c8
  kernel: SyS_read+0x50/0xb0
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006eff4  /system/lib64/libc.so (read+4)
  native: #01 pc 000000000002f698  /system/lib64/libjavacore.so (Linux_readBytes(_JNIEnv*, _jobject*, _jobject*, _jobject*, int, int)+192)
  at libcore.io.Linux.readBytes(Native method)
  at libcore.io.Linux.read(Linux.java:184)
  at libcore.io.BlockGuardOs.read(BlockGuardOs.java:254)
  at android.system.Os.read(Os.java:414)
  at android.net.apf.ApfFilter$ReceiveThread.run(ApfFilter.java:199)

"Thread-92298" prio=5 tid=178 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14149fb8 self=0x7211c1d800
  | sysTid=12636 nice=0 cgrp=default sched=0/0 handle=0x7080d2c4f0
  | state=S schedstat=( 1095990 1132241 13 ) utm=0 stm=0 core=5 HZ=100
  | stack=0x7080c29000-0x7080c2b000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: __skb_wait_for_more_packets+0x114/0x178
  kernel: __skb_recv_datagram+0x70/0xc4
  kernel: skb_recv_datagram+0x3c/0x5c
  kernel: packet_recvmsg+0x6c/0x308
  kernel: sock_read_iter+0xc8/0xf4
  kernel: __vfs_read+0xe8/0x12c
  kernel: vfs_read+0xcc/0x2c8
  kernel: SyS_read+0x50/0xb0
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006eff4  /system/lib64/libc.so (read+4)
  native: #01 pc 000000000002f698  /system/lib64/libjavacore.so (Linux_readBytes(_JNIEnv*, _jobject*, _jobject*, _jobject*, int, int)+192)
  at libcore.io.Linux.readBytes(Native method)
  at libcore.io.Linux.read(Linux.java:184)
  at libcore.io.BlockGuardOs.read(BlockGuardOs.java:254)
  at android.system.Os.read(Os.java:414)
  at android.net.dhcp.DhcpClient$ReceiveThread.run(DhcpClient.java:377)

"OkHttp ConnectionPool" daemon prio=5 tid=185 WaitingForGcToComplete
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14a40848 self=0x720ee2f400
  | sysTid=381 nice=0 cgrp=default sched=0/0 handle=0x70811d54f0
  | state=S schedstat=( 713804 310781 4 ) utm=0 stm=0 core=5 HZ=100
  | stack=0x70810d2000-0x70810d4000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f00e4  /system/lib64/libart.so (art::gc::Heap::WaitForGcToCompleteLocked(art::gc::GcCause, art::Thread*)+344)
  native: #03 pc 00000000001fba50  /system/lib64/libart.so (art::gc::Heap::WaitForGcToComplete(art::gc::GcCause, art::Thread*)+408)
  native: #04 pc 00000000001f8cf8  /system/lib64/libart.so (art::gc::Heap::AllocateInternalWithGc(art::Thread*, art::gc::AllocatorType, bool, unsigned long, unsigned long*, unsigned long*, unsigned long*, art::ObjPtr<art::mirror::Class>*)+156)
  native: #05 pc 000000000050e850  /system/lib64/libart.so (artAllocObjectFromCodeInitializedRegionTLAB+380)
  native: #06 pc 000000000056465c  /system/lib64/libart.so (art_quick_alloc_object_initialized_region_tlab+108)
  at java.util.ArrayDeque.iterator(ArrayDeque.java:588)
  at com.android.okhttp.ConnectionPool.cleanup(ConnectionPool.java:246)
  - locked <0x08f608bc> (a com.android.okhttp.ConnectionPool)
  at com.android.okhttp.ConnectionPool$1.run(ConnectionPool.java:96)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1167)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)

"AsyncTask #36709" prio=5 tid=180 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14d149c8 self=0x7211c94400
  | sysTid=4738 nice=0 cgrp=default sched=0/0 handle=0x708411b4f0
  | state=S schedstat=( 3931924 16620626 18 ) utm=0 stm=0 core=7 HZ=100
  | stack=0x7084018000-0x708401a000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: binder_thread_read+0xa78/0x11a0
  kernel: binder_ioctl+0x920/0xb08
  kernel: do_vfs_ioctl+0xb8/0x8d8
  kernel: SyS_ioctl+0x84/0x98
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e5bc  /system/lib64/libc.so (__ioctl+4)
  native: #01 pc 0000000000029544  /system/lib64/libc.so (ioctl+136)
  native: #02 pc 000000000001e22c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::talkWithDriver(bool)+240)
  native: #03 pc 000000000001e884  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::waitForResponse(android::hardware::Parcel*, int*)+324)
  native: #04 pc 0000000000012204  /system/lib64/libhwbinder.so (android::hardware::BpHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+312)
  native: #05 pc 00000000000c9764  /system/lib64/android.hardware.gnss@1.0.so (android::hardware::gnss::V1_0::BpHwGnssXtra::_hidl_injectXtraData(android::hardware::IInterface*, android::hardware::details::HidlInstrumentor*, android::hardware::hidl_string const&)+244)
  native: #06 pc 000000000005d5c4  /system/lib64/libandroid_servers.so (android::android_location_GnssLocationProvider_inject_xtra_data(_JNIEnv*, _jobject*, _jbyteArray*, int)+268)
  at com.android.server.location.GnssLocationProvider.native_inject_xtra_data(Native method)
  at com.android.server.location.GnssLocationProvider.access$2300(GnssLocationProvider.java:112)
  at com.android.server.location.GnssLocationProvider$10.run(GnssLocationProvider.java:1140)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1167)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)

"OkHttp ConnectionPool" daemon prio=5 tid=179 TimedWaiting
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x16184500 self=0x7219cbf800
  | sysTid=4996 nice=0 cgrp=default sched=0/0 handle=0x7080f474f0
  | state=S schedstat=( 108707664 3130885 522 ) utm=9 stm=1 core=5 HZ=100
  | stack=0x7080e44000-0x7080e46000 stackSize=1041KB
  | held mutexes=
  at java.lang.Object.wait(Native method)
  - waiting on <0x00fec39a> (a com.android.okhttp.ConnectionPool)
  at com.android.okhttp.ConnectionPool$1.run(ConnectionPool.java:103)
  - locked <0x00fec39a> (a com.android.okhttp.ConnectionPool)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1167)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)

"PowerManagerSer" prio=5 (not attached)
  | sysTid=4942 nice=-4 cgrp=default
  | state=S schedstat=( 2522338493 560454952 7365 ) utm=0 stm=252 core=6 HZ=100
  kernel: __switch_to+0xa4/0xfc
  kernel: pm_get_wakeup_count+0x68/0xe4
  kernel: wakeup_count_show+0x28/0x70
  kernel: kobj_attr_show+0x14/0x24
  kernel: sysfs_kf_seq_show+0x84/0x148
  kernel: kernfs_seq_show+0x28/0x30
  kernel: seq_read+0x184/0x484
  kernel: kernfs_fop_read+0x11c/0x1b0
  kernel: __vfs_read+0x38/0x12c
  kernel: vfs_read+0xcc/0x2c8
  kernel: SyS_read+0x50/0xb0
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006eff8  /system/lib64/libc.so (read+8)
  native: #01 pc 000000000000702c  /system/lib64/libbase.so (android::base::ReadFdToString(int, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>*)+144)
  native: #02 pc 0000000000002298  /system/lib64/libsuspend.so (suspend_thread_func(void*)+168)
  native: #03 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  native: #04 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
----- end 1471 -----
```
</details>

&nbsp;&nbsp;&nbsp;   
检查各个线程在虚拟机内部的状态后，看到一个比较奇怪的现象：

```c++
"Binder:filter-perf-event"` `prio=``5` `tid=``4` `WaitingForGcThreadFlip
"HeapTaskDaemon"` `daemon prio=``5` `tid=``9` `WaitingForGcThreadFlip
"PowerManagerService"` `prio=``5` `tid=``24` `WaitingForGcThreadFlip
"HwBinder:1471_1"` `prio=``5` `tid=``35` `WaitingForGcThreadFlip
"WifiStateMachine"` `prio=``5` `tid=``56` `WaitingForGcThreadFlip
"Binder:1471_3"` `prio=``5` `tid=``92` `WaitingForGcThreadFlip
"Binder:1471_5"` `prio=``5` `tid=``105` `WaitingForGcThreadFlip
"Binder:1471_7"` `prio=``5` `tid=``107` `WaitingForGcThreadFlip
"Binder:1471_A"` `prio=``5` `tid=``120` `WaitingForGcThreadFlip
"Binder:1471_D"` `prio=``5` `tid=``123` `WaitingForGcThreadFlip
"Binder:1471_E"` `prio=``5` `tid=``124` `WaitingForGcThreadFlip
"Binder:1471_11"` `prio=``5` `tid=``127` `WaitingForGcThreadFlip
"Binder:1471_17"` `prio=``5` `tid=``133` `WaitingForGcThreadFlip
"Binder:1471_18"` `prio=``5` `tid=``134` `WaitingForGcThreadFlip
"Binder:1471_19"` `prio=``5` `tid=``135` `WaitingForGcThreadFlip
"HwBinder:1471_4"` `prio=``5` `tid=``12` `WaitingForGcThreadFlip
"Binder:1471_20"` `prio=``5` `tid=``146` `WaitingForGcThreadFlip
"HwBinder:1471_5"` `prio=``5` `tid=``34` `WaitingForGcToComplete
"ADB-JDWP Connection Control Thread"` `daemon prio=``0` `tid=``5` `WaitingForGcToComplete
"android.io"` `prio=``5` `tid=``21` `WaitingForGcToComplete
"CpuTracker"` `prio=``5` `tid=``23` `WaitingForGcToComplete
"UEventObserver"` `prio=``5` `tid=``36` `WaitingForGcToComplete
"HwBinder:1471_2"` `prio=``5` `tid=``43` `WaitingForGcToComplete
"HwBinder:1471_3"` `prio=``5` `tid=``44` `WaitingForGcToComplete
"NetdConnector"` `prio=``5` `tid=``50` `WaitingForGcToComplete
"WifiService"` `prio=``5` `tid=``55` `WaitingForGcToComplete
"DeviceStorageMonitorService"` `prio=``5` `tid=``67` `WaitingForGcToComplete
"SecurityWriteHandlerThread"` `prio=``5` `tid=``72` `WaitingForGcToComplete
"watchdog"` `prio=``5` `tid=``101` `WaitingForGcToComplete
"HwBinder:1471_5"` `prio=``5` `tid=``34` `WaitingForGcToComplete
"Timer-20"` `prio=``5` `tid=``170` `WaitingForGcToComplete
"IpClient.wlan0"` `prio=``5` `tid=``176` `WaitingForGcToComplete
"OkHttp ConnectionPool"` `daemon prio=``5` `tid=``185` `WaitingForGcToComplete
...
"main"` `prio=``5` `tid=``1` `Blocked
"Binder:1471_1"` `prio=``5` `tid=``10` `Blocked
"Binder:1471_2"` `prio=``5` `tid=``11` `Blocked
"android.bg"` `prio=``5` `tid=``13` `Blocked
"ActivityManager"` `prio=``5` `tid=``14` `Blocked
"batterystats-worker"` `prio=``5` `tid=``18` `Blocked
"android.fg"` `prio=``5` `tid=``20` `Blocked
"android.display"` `prio=``5` `tid=``22` `Blocked
"AlarmManager"` `prio=``5` `tid=``40` `Blocked
"InputDispatcher"` `prio=``10` `tid=``46` `Blocked
"InputReader"` `prio=``10` `tid=``47` `Blocked
"NetworkPolicy.uid"` `prio=``5` `tid=``53` `Blocked
"Binder:1471_4"` `prio=``5` `tid=``93` `Blocked
"Binder:1471_6"` `prio=``5` `tid=``106` `Blocked
"Binder:1471_8"` `prio=``5` `tid=``108` `Blocked
"Binder:1471_9"` `prio=``5` `tid=``118` `Blocked
"Binder:1471_B"` `prio=``5` `tid=``121` `Blocked
"Binder:1471_C"` `prio=``5` `tid=``122` `Blocked
"Binder:1471_F"` `prio=``5` `tid=``125` `Blocked
"Binder:1471_10"` `prio=``5` `tid=``126` `Blocked
"Binder:1471_12"` `prio=``5` `tid=``128` `Blocked
"Binder:1471_13"` `prio=``5` `tid=``129` `Blocked
"Binder:1471_14"` `prio=``5` `tid=``130` `Blocked
"Binder:1471_15"` `prio=``5` `tid=``131` `Blocked
"Binder:1471_16"` `prio=``5` `tid=``132` `Blocked
"Binder:1471_1A"` `prio=``5` `tid=``136` `Blocked
"Binder:1471_1B"` `prio=``5` `tid=``140` `Blocked
"Binder:1471_1C"` `prio=``5` `tid=``117` `Blocked
"Binder:1471_1D"` `prio=``5` `tid=``141` `Blocked
"Binder:1471_1E"` `prio=``5` `tid=``144` `Blocked
"Binder:1471_1F"` `prio=``5` `tid=``145` `Blocked
"NetworkMonitorNetworkAgentInfo [WIFI () - 950]"` `prio=``5` `tid=``149` `Blocked
```
一堆线程都是gc相关的状态，具体什么意思，我也不关心，还是再继续看下blocked的线程，都具体卡在什么地方：
```java
"Binder:1471_6" prio=5 tid=106 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064288 self=0x721bdfb000
  | sysTid=2126 nice=0 cgrp=default sched=0/0 handle=0x72107ff4f0
  | state=S schedstat=( 5605933458050 5415448290382 12052578 ) utm=475916 stm=84677 core=5 HZ=100
  | stack=0x7210704000-0x7210706000 stackSize=1009KB
  | held mutexes=
  at com.android.server.net.NetworkPolicyManagerService.isUidNetworkingBlockedInternal(NetworkPolicyManagerService.java:4825)
  - waiting to lock <0x05e68352> (a java.lang.Object) held by thread 53
  at com.android.server.net.NetworkPolicyManagerService.access$3600(NetworkPolicyManagerService.java:291)
  at com.android.server.net.NetworkPolicyManagerService$NetworkPolicyManagerInternalImpl.isUidNetworkingBlocked(NetworkPolicyManagerService.java:4900)
  at com.android.server.ConnectivityService.isNetworkWithLinkPropertiesBlocked(ConnectivityService.java:1133)
  at com.android.server.ConnectivityService.filterNetworkStateForUid(ConnectivityService.java:1163)
  at com.android.server.ConnectivityService.getActiveNetworkInfo(ConnectivityService.java:1185)
  at android.net.IConnectivityManager$Stub.onTransact(IConnectivityManager.java:85)
  at android.os.Binder.execTransact(Binder.java:728)
 
"Binder:1471_8" prio=5 tid=108 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14064398 self=0x7219dd9000
  | sysTid=2168 nice=0 cgrp=default sched=0/0 handle=0x720fdff4f0
  | state=S schedstat=( 5601724562758 5464273391739 12340199 ) utm=473400 stm=86772 core=6 HZ=100
  | stack=0x720fd04000-0x720fd06000 stackSize=1009KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.activityPaused(ActivityManagerService.java:8527)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:225)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)
 
"NetworkPolicy.uid" prio=5 tid=53 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x1405f790 self=0x72163fc000
  | sysTid=1881 nice=-2 cgrp=default sched=0/0 handle=0x721767d4f0
  | state=S schedstat=( 992941159886 2687927167537 3629569 ) utm=24231 stm=75063 core=5 HZ=100
  | stack=0x721757a000-0x721757c000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService$LocalService.notifyNetworkPolicyRulesUpdated(ActivityManagerService.java:27503)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at com.android.server.net.NetworkPolicyManagerService.handleUidChanged(NetworkPolicyManagerService.java:4461)
  - locked <0x05e68352> (a java.lang.Object)
  at com.android.server.net.NetworkPolicyManagerService$18.handleMessage(NetworkPolicyManagerService.java:4435)
  at android.os.Handler.dispatchMessage(Handler.java:102)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
  at com.android.server.ServiceThread.run(ServiceThread.java:44)
```
接着看 0x05e68352 和  0x00c6c1f5 这俩monitor锁的持有线程：
```java
"Binder:1471_20" prio=5 tid=146 WaitingForGcThreadFlip
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14147028 self=0x72126b5800
  | sysTid=18045 nice=-2 cgrp=default sched=0/0 handle=0x72049824f0
  | state=S schedstat=( 6101767900274 5905637387083 13051781 ) utm=516502 stm=93674 core=7 HZ=100
  | stack=0x7204887000-0x7204889000 stackSize=1009KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: futex_wait_queue_me+0xc4/0x13c
  kernel: futex_wait+0xe4/0x204
  kernel: do_futex+0x168/0x80c
  kernel: SyS_futex+0x90/0x1b8
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000001ef2c  /system/lib64/libc.so (syscall+28)
  native: #01 pc 00000000000d855c  /system/lib64/libart.so (art::ConditionVariable::WaitHoldingLocks(art::Thread*)+148)
  native: #02 pc 00000000001f0680  /system/lib64/libart.so (art::gc::Heap::IncrementDisableThreadFlip(art::Thread*)+516)
  native: #03 pc 0000000000384fe4  /system/lib64/libart.so (art::JNI::GetStringCritical(_JNIEnv*, _jstring*, unsigned char*)+692)
  native: #04 pc 000000000012e268  /system/lib64/libandroid_runtime.so (android::android_os_Parcel_writeString(_JNIEnv*, _jclass*, long, _jstring*)+64)
  at android.os.Parcel.nativeWriteString(Native method)
  at android.os.Parcel$ReadWriteHelper.writeString(Parcel.java:369)
  at android.os.Parcel.writeString(Parcel.java:707)
  at android.content.pm.PackageItemInfo.writeToParcel(PackageItemInfo.java:652)
  at android.content.pm.ApplicationInfo.writeToParcel(ApplicationInfo.java:1513)
  at android.app.IApplicationThread$Stub$Proxy.bindApplication(IApplicationThread.java:943)
  at com.android.server.am.ActivityManagerService.attachApplicationLocked(ActivityManagerService.java:8146)
  at com.android.server.am.ActivityManagerService.attachApplication(ActivityManagerService.java:8255)
  - locked <0x00c6c1f5> (a com.android.server.am.ActivityManagerService)
  at android.app.IActivityManager$Stub.onTransact(IActivityManager.java:199)
  at com.android.server.am.ActivityManagerService.onTransact(ActivityManagerService.java:3399)
  at android.os.Binder.execTransact(Binder.java:728)
```
可以看到还是owner线程正是之前 WaitingForGcThreadFlip 中的一员，那么下一步通过gdb看下这一类线程具体卡在哪一行代码上：
- 根据机器的版本号确认symbol文件后，通过公司同事分享的脚本一行命令就可以attach到system_server进程上
```c++
$ ~/Documents/gdb_native_tools/droid.py attach /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols system_server
 
process: system_server, pid(1471), parent(zygote64)
gdbserver:/data/local/tmp/gdbserver64
bin_path: /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/
solib:    /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/lib64/
bin:      /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/app_process64
 
Attached; pid = 1471
gdbserver: Unable to determine the number of hardware watchpoints available.
gdbserver: Unable to determine the number of hardware breakpoints available.
Listening on port 1234
 
GNU gdb (GDB) 7.11
Copyright (C) 2016 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "x86_64-linux-gnu".
Type "show configuration" for configuration details.
For bug reporting instructions, please see:
<http://www.gnu.org/software/gdb/bugs/>.
Find the GDB manual and other documentation resources online at:
<http://www.gnu.org/software/gdb/documentation/>.
For help, type "help".
Type "apropos word" to search for commands related to "word".
Reading symbols from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/app_process64...done.
Remote debugging using localhost:1234
Remote debugging from host 127.0.0.1
warning: .dynamic section for "/home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/app_process64" is not at the expected address (wrong library or version mismatch?)
warning: .dynamic section for "/home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/lib64/libandroid_runtime.so" is not at the expected address (wrong library or version mismatch?)
warning: .dynamic section for "/home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/lib64/libcutils.so" is not at the expected address (wrong library or version mismatch?)
warning: .dynamic section for "/home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/lib64/libaudioclient.so" is not at the expected address (wrong library or version mismatch?)
warning: .dynamic section for "/home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/lib64/libcutils.so" is not at the expected address (wrong library or version mismatch?)
warning: Could not load shared library symbols for 15 libraries, e.g. /system/lib64/libclang_rt.ubsan_standalone-aarch64-android.so.
Use the "info sharedlibrary" command to see the complete listing.
Do you need "set solib-search-path" or "set sysroot"?
Reading symbols from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/app_process64...done.
Reading symbols from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/linker64...done.
......
syscall () at bionic/libc/arch-arm64/bionic/syscall.S:41
41  bionic/libc/arch-arm64/bionic/syscall.S: No such file or directory.
Source directories searched: /mnt/miui/v10-p-dipper-alpha:$cdir:$cwd
#0  syscall () at bionic/libc/arch-arm64/bionic/syscall.S:41
#1  0x0000007238a80560 in art::futex (uaddr=0x723961df68, op=0, val=20935915, timeout=0x7fc723ee90, uaddr2=0x7fc723ee90, val3=0) at art/runtime/base/mutex-inl.h:43
#2  art::ConditionVariable::WaitHoldingLocks (this=0x723961df58, self=0x7239614c00) at art/runtime/base/mutex.cc:953
#3  0x0000007238d6241c in art::Monitor::Lock<(art::LockReason)1> (this=0x723961df20, self=0x7239614c00) at art/runtime/monitor.cc:559
#4  0x0000007238d687a8 in art::Monitor::MonitorEnter (self=0x7239614c00, obj=<optimized out>, trylock=<optimized out>) at art/runtime/monitor.cc:1462
#5  0x0000007238ec40fc in art::mirror::Object::MonitorEnter (this=0x62 <_DYNAMIC+98>, self=0x7239614c00) at art/runtime/mirror/object-inl.h:98
#6  artLockObjectFromCode (obj=0x62 <_DYNAMIC+98>, self=0x7239614c00) at art/runtime/entrypoints/quick/quick_lock_entrypoints.cc:32
#7  0x0000007238f04e9c in art_quick_lock_object () at art/runtime/arch/arm64/quick_entrypoints_arm64.S:1510
#8  0x00000072207cf6a4 in ?? ()
Backtrace stopped: not enough registers or memory available to unwind further
/home/pip/Documents/gdb_native_tools/gdb-script/init.gdb: No such file or directory.
/home/pip/Documents/gdb_native_tools/shadow/gdb_driver.py: No such file or directory.
(gdb) handle SIG35 nostop noprint pass
Signal        Stop  Print   Pass to program Description
SIG35         No    No  Yes     Real-time event 35
(gdb) handle SIG33 nostop noprint pass
Signal        Stop  Print   Pass to program Description
SIG33         No    No  Yes     Real-time event 33
```
*tips：handle SIG35 nostop noprint pass 是为了不处理android平台上用于抓native trace的 sig35 信号，减小我们的调试过程意外中断的可能性（只是个习惯, 这个问题中其实不做也没关系）*

- 切换到gc线程
```c++
(gdb) thread 9
[Switching to thread 9 (Thread 1471.1484)]
#0  syscall () at bionic/libc/arch-arm64/bionic/syscall.S:41
41      svc     #0
(gdb) bt
#0  syscall () at bionic/libc/arch-arm64/bionic/syscall.S:41
#1  0x0000007238a80560 in art::futex (uaddr=0x7239723910, op=0, val=93152, timeout=0x7221a89ab0, uaddr2=0x7221a89ab0, val3=0) at art/runtime/base/mutex-inl.h:43
#2  art::ConditionVariable::WaitHoldingLocks (this=0x7239723900, self=0x723966b000) at art/runtime/base/mutex.cc:953
#3  0x0000007238b98d54 in art::gc::Heap::ThreadFlipBegin (this=0x72396b7600, self=0x723966b000) at art/runtime/gc/heap.cc:845 // <<<<<<<<<<<<<<<<<<<<<<<
#4  0x0000007238e52204 in art::ThreadList::FlipThreadRoots (this=<optimized out>, thread_flip_visitor=0x7221a89ca0, flip_callback=<optimized out>, collector=
    0x7239716500, pause_listener=<optimized out>) at art/runtime/thread_list.cc:591
#5  0x0000007238b65cc4 in art::gc::collector::ConcurrentCopying::FlipThreadRoots (this=0x7239716500) at art/runtime/gc/collector/concurrent_copying.cc:620
#6  0x0000007238b64c50 in art::gc::collector::ConcurrentCopying::RunPhases (this=0x7239716500) at art/runtime/gc/collector/concurrent_copying.cc:178
#7  0x0000007238b7af80 in art::gc::collector::GarbageCollector::Run (this=0x7239716500, gc_cause=<optimized out>, clear_soft_references=<optimized out>)
    at art/runtime/gc/collector/garbage_collector.cc:96
#8  0x0000007238b9d93c in art::gc::Heap::CollectGarbageInternal (this=0x72396b7600, gc_type=art::gc::collector::kGcTypeFull, gc_cause=art::gc::kGcCauseBackground,
    clear_soft_references=false) at art/runtime/gc/heap.cc:2616
#9  0x0000007238baeeb8 in art::gc::Heap::ConcurrentGC (this=0x72396b7600, self=<optimized out>, cause=art::gc::kGcCauseBackground, force_full=false)
    at art/runtime/gc/heap.cc:3621
#10 0x0000007238bb4524 in art::gc::Heap::ConcurrentGCTask::Run (this=<optimized out>, self=0x0 <_DYNAMIC>) at art/runtime/gc/heap.cc:3582
#11 0x0000007238bd692c in art::gc::TaskProcessor::RunAllTasks (this=0x72396bb100, self=0x723966b000) at art/runtime/gc/task_processor.cc:129
#12 0x0000000072a7e3f0 in dalvik.system.VMRuntime.clampGrowthLimit [DEDUPED] ()
   from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/framework/arm64/boot-core-libart.oat
#13 0x0000000072c20bd8 in java.lang.Daemons$HeapTaskDaemon.runInternal ()
   from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/framework/arm64/boot-core-libart.oat
#14 0x0000000072a80c40 in java.lang.Daemons$Daemon.run ()
   from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/framework/arm64/boot-core-libart.oat
#15 0x0000000071baa4dc in java.lang.Thread.run ()
   from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/framework/arm64/boot-core-oj.oat
#16 0x0000007238f0498c in art_quick_invoke_stub () at art/runtime/arch/arm64/quick_entrypoints_arm64.S:1702
#17 0x0000007238a78524 in art::ArtMethod::Invoke (this=0x6ff68ad8, self=0x723966b000, args=<optimized out>, args_size=<optimized out>, result=0x7221a8a310,
    shorty=0x7269daa9 "V") at art/runtime/art_method.cc:374
#18 0x0000007238e07258 in art::(anonymous namespace)::InvokeWithArgArray (soa=..., method=0x6ff68ad8, arg_array=0x7221a8a318, result=<optimized out>,
    shorty=0x7269daa9 "V") at art/runtime/reflection.cc:456
#19 0x0000007238e08314 in art::InvokeVirtualOrInterfaceWithJValues (soa=..., obj=0x5 <_DYNAMIC+5>, mid=<optimized out>, args=0x0 <_DYNAMIC>)
    at art/runtime/reflection.cc:548
#20 0x0000007238e36764 in art::Thread::CreateCallback (arg=0x723966b000) at art/runtime/thread.cc:473
#21 0x00000072bb501db0 in __pthread_start (arg=0x7221a8a4f0) at bionic/libc/bionic/pthread_create.cpp:254
#22 0x00000072bb4a378c in __start_thread (fn=0x72bb501d88 <__pthread_start(void*)>, arg=0x7221a8a4f0) at bionic/libc/bionic/clone.cpp:52
```
结合代码： art/runtime/gc/heap.cc#845
```c++
void Heap::ThreadFlipBegin(Thread* self) {
  // Supposed to be called by GC. Set thread_flip_running_ to be true. If disable_thread_flip_count_
  // > 0, block. Otherwise, go ahead.
  CHECK(kUseReadBarrier);
  ScopedThreadStateChange tsc(self, kWaitingForGcThreadFlip);
  MutexLock mu(self, *thread_flip_lock_);
  bool has_waited = false;
  uint64_t wait_start = NanoTime();
  CHECK(!thread_flip_running_);
  // Set this to true before waiting so that frequent JNI critical enter/exits won't starve
  // GC. This like a writer preference of a reader-writer lock.
  thread_flip_running_ = true;
  while (disable_thread_flip_count_ > 0) { // <<<<<<<<<<<<
    has_waited = true;
    thread_flip_cond_->Wait(self); // <<<<<<<<<<<<<
  }
  if (has_waited) {
    uint64_t wait_time = NanoTime() - wait_start;
    total_wait_time_ += wait_time;
    if (wait_time > long_pause_log_threshold_) {
      LOG(INFO) << __FUNCTION__ << " blocked for " << PrettyDuration(wait_time);
    }
  }
}
```
既然在等待一个condition，那么 disable_thread_flip_count_ 肯定是大于0的，我们可以打印一下这个变量的值：
```bash
(gdb) print disable_thread_flip_count_
$1 = 1
```
果然它是1，正常情况下，当前线程在thread_flip_cond_这个条件上wait一段时间后，肯定会有一个线程会去notify它，来唤醒处于wait状态的线程；

- 那么，接下来自然是快速过一下源码，看看都有哪些函数会去操作thread_flip_cond_：

```c++
void Heap::ThreadFlipEnd(Thread* self) {
  // Supposed to be called by GC. Set thread_flip_running_ to false and potentially wake up mutators
  // waiting before doing a JNI critical.
  CHECK(kUseReadBarrier);
  MutexLock mu(self, *thread_flip_lock_);
  CHECK(thread_flip_running_);
  thread_flip_running_ = false;
  // Potentially notify mutator threads blocking to enter a JNI critical section.
  thread_flip_cond_->Broadcast(self);  // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
}
 
void Heap::DecrementDisableThreadFlip(Thread* self) {
  // Supposed to be called by mutators. Decrement disable_thread_flip_count_ and potentially wake up
  // the GC waiting before doing a thread flip.
  CHECK(kUseReadBarrier);
  self->DecrementDisableThreadFlipCount();
  bool is_outermost = self->GetDisableThreadFlipCount() == 0;
  if (!is_outermost) {
    // If this is not an outermost JNI critical exit, we don't need to decrement the global counter.
    // The global counter is decremented only once for a thread for the outermost exit.
    return;
  }
  MutexLock mu(self, *thread_flip_lock_);
  CHECK_GT(disable_thread_flip_count_, 0U);
  --disable_thread_flip_count_;
  if (disable_thread_flip_count_ == 0) {
    // Potentially notify the GC thread blocking to begin a thread flip.
    thread_flip_cond_->Broadcast(self); // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  }
}
```
再看一下各个线程的backtrace，确认了，没有哪个在调用上面两个任意一个

- 那些处于WaitingForGcThreadFlip的线程block在哪？
```c++
(gdb) t 23
[Switching to thread 23 (Thread 1471.1692)]
#0  syscall () at bionic/libc/arch-arm64/bionic/syscall.S:41
41      svc     #0
(gdb) bt
#0  syscall () at bionic/libc/arch-arm64/bionic/syscall.S:41
#1  0x0000007238a80560 in art::futex (uaddr=0x7239723910, op=0, val=93152, timeout=0x721cbe2850, uaddr2=0x721cbe2850, val3=0) at art/runtime/base/mutex-inl.h:43
#2  art::ConditionVariable::WaitHoldingLocks (this=0x7239723900, self=0x721d26a000) at art/runtime/base/mutex.cc:953
#3  0x0000007238b98684 in art::gc::Heap::IncrementDisableThreadFlip (this=0x72396b7600, self=0x721d26a000) at art/runtime/gc/heap.cc:798
#4  0x0000007238d2cfe8 in art::JNI::GetStringCritical (env=<optimized out>, java_string=<optimized out>, is_copy=0x0 <_DYNAMIC>) at art/runtime/jni_internal.cc:1887
#5  0x00000072bae3177c in android::sp<android::IGraphicBufferProducer>::~sp (this=0x0 <_DYNAMIC>) at system/core/libutils/include/utils/StrongPointer.h:156
#6  android::nativeCreateScoped (env=<optimized out>, clazz=<optimized out>, surfaceObject=<optimized out>)
    at frameworks/base/core/jni/android_view_SurfaceSession.cpp:51
#7  0x00000000748c94ac in android.filterfw.format.ImageFormat.create ()
   from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/framework/arm64/boot-framework.oat
#8  0x0000000000000000 in ?? () from /home/pip/Downloads/e8-V10.3.3.0.PECCNXM-gcflip-hang/out/target/product/equuleus/symbols/system/bin/app_process64
```
art/runtime/gc/heap.cc:798 对应的代码：
```c++
void Heap::IncrementDisableThreadFlip(Thread* self) {
  // Supposed to be called by mutators. If thread_flip_running_ is true, block. Otherwise, go ahead.
  CHECK(kUseReadBarrier);
  bool is_nested = self->GetDisableThreadFlipCount() > 0;
  self->IncrementDisableThreadFlipCount();
  if (is_nested) {
    // If this is a nested JNI critical section enter, we don't need to wait or increment the global
    // counter. The global counter is incremented only once for a thread for the outermost enter.
    return;
  }
  ScopedThreadStateChange tsc(self, kWaitingForGcThreadFlip);     // <<<<<<<<<<<<<<<<<<<<<<< 改变线程状态
  MutexLock mu(self, *thread_flip_lock_);
  bool has_waited = false;
  uint64_t wait_start = NanoTime();
  if (thread_flip_running_) {
    ScopedTrace trace("IncrementDisableThreadFlip");
    while (thread_flip_running_) {
      has_waited = true;
      thread_flip_cond_->Wait(self); // <<<<<<<<<<<<<<<<<<<<
    }
  }
  ++disable_thread_flip_count_;
  if (has_waited) {
    uint64_t wait_time = NanoTime() - wait_start;
    total_wait_time_ += wait_time;
    if (wait_time > long_pause_log_threshold_) {
      LOG(INFO) << __FUNCTION__ << " blocked for " << PrettyDuration(wait_time);
    }
  }
}
```
所以到这儿，我们清楚的一点是，肯定是由于某个线程没有正常调用 DecrementDisableThreadFlip() 函数，导致 disable_thread_flip_count_ 一直不为0；

- disable_thread_flip_count_ 一直不为 0 这个锅应该是谁的？
仔细看一下上面这个函数的代码，不仅全局有个disable_thread_flip_count_， 同时每个线程还有thread local的 disable_thread_flip_count，每次调用IncrementDisableThreadFlip()开始的时候，都会先执行Thread::Current()->IncrementDisableThreadFlipCount()，看下它的代码：
```c++
// art/runtime/thread.h
uint32_t GetDisableThreadFlipCount() const {
  CHECK(kUseReadBarrier);
  return tls32_.disable_thread_flip_count;
}
```
YEAH！下面只需要逐个遍历art里面每个线程，把 tls32_.disable_thread_flip_count > 1的部分打印出来：
稍微修改一下gdb脚本下的 art.gdb脚本里的art_dump_thread_list_base函数：
```bash
define art_dump_thread_list
    art_dump_thread_list_base 0
end
 
define art_dump_thread_list_base
    set $dump_mutex = $arg0
    #  第一个节点
    set $first = ('art::Runtime'::instance_)->thread_list_->list_->__end_->__next_
    printf "\n  Id    Thread Id   art::Thread*    disable_flip_count    STATE         FLAGS                NAME             SUSPEND_COUNT           MUTEX\n"
 
    set $list_node = 0
    set $count = 1
 
    while $list_node != $first
        if $list_node == 0
            set $list_node = $first
        end
         
        set $thread = ('art::Thread'*)(*(void**)((uint64_t)$list_node + 2*sizeof(void*)))
        set $flip_count = (('art::Thread'*)$thread)->tls32_->disable_thread_flip_count
        if $flip_count != 0  # <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< 1 
            set $thread_id = (('art::Thread'*)$thread)->tls32_->tid
 
            #printf "monitor_enter_object: 0x%lx", $thread->tlsPtr_.monitor_enter_object
            printf "%4d     %6d     %p   ", $count, $thread_id, $thread
 
            printf "         %d        ", $flip_count # <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< 2
 
            thread_print_state $thread
 
            printf "              "
            thread_print_name $thread
            printf "              "
            thread_print_suspend_count $thread
 
            if $dump_mutex == 1
                thread_print_mutex $thread
            end
 
            printf "\n"
        end
 
        set $list_node = $list_node->__next_
        set $count = $count + 1
 
        if $list_node == $first
            loop_break
        end
    end
end
```
然后重新导入脚本然后执行这个函数即可：
```bash
(gdb) source /home/pip/Documents/gdb_native_tools/art.gdb
(gdb) art_dump_thread_list
  Id    Thread Id   art::Thread*    disable_flip_count    STATE                       NAME                        SUSPEND_COUNT        
   4       1479     0x723973c800            1          kWaitingForGcThreadFlip     Binder:filter-perf-event     0
  23       1692     0x721d26a000            1          kWaitingForGcThreadFlip     PowerManagerService          0
  31       1825     0x722b7ab800            1          kWaitingForGcThreadFlip     HwBinder:1471_1              0
  52       1884     0x721c426c00            1          kWaitingForGcThreadFlip     WifiStateMachine             0
  88       1938     0x721bc96800            1          kWaitingForGcThreadFlip     Binder:1471_3                0
  98       2125     0x721c54d000            1          kWaitingForGcThreadFlip     Binder:1471_5                0
 100       2166     0x721a129800            1          kWaitingForGcThreadFlip     Binder:1471_7                0
 113       2894     0x7219cc1000            1          kWaitingForGcThreadFlip     Binder:1471_A                0
 116       2949     0x721273ec00            1          kWaitingForGcThreadFlip     Binder:1471_D                0
 117       2950     0x7219cc0400            1          kWaitingForGcThreadFlip     Binder:1471_E                0
 120       3089     0x720b025000            1          kWaitingForGcThreadFlip     Binder:1471_11               0
 126       3135     0x720c454800            1          kWaitingForGcThreadFlip     Binder:1471_17               0
 127       3140     0x721929cc00            1          kWaitingForGcThreadFlip     Binder:1471_18               0
 128       3142     0x720eb42000            1          kWaitingForGcThreadFlip     Binder:1471_19               0
 132       8981     0x7219d25800            1          kWaitingForGcThreadFlip     HwBinder:1471_4              0
 142      18045     0x72126b5800            1          kWaitingForGcThreadFlip     Binder:1471_20               0
 181       4738     0x7211c94400            1          kNative                     AsyncTask #36709             0
```
最后那个 AsyncTask #36709  十分可疑，别的线程的disable_flip_count 为1的原因是正在调用 IncrementDisableThreadFlip（）函数，OK，接着看下它在执行什么函数：
- 嫌疑人 “AsyncTask #36709” 干了些什么？
```c++
"AsyncTask #36709" prio=5 tid=180 Native
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x14d149c8 self=0x7211c94400
  | sysTid=4738 nice=0 cgrp=default sched=0/0 handle=0x708411b4f0
  | state=S schedstat=( 3931924 16620626 18 ) utm=0 stm=0 core=7 HZ=100
  | stack=0x7084018000-0x708401a000 stackSize=1041KB
  | held mutexes=
  kernel: __switch_to+0xa4/0xfc
  kernel: binder_thread_read+0xa78/0x11a0
  kernel: binder_ioctl+0x920/0xb08
  kernel: do_vfs_ioctl+0xb8/0x8d8
  kernel: SyS_ioctl+0x84/0x98
  kernel: __sys_trace+0x4c/0x4c
  native: #00 pc 000000000006e5bc  /system/lib64/libc.so (__ioctl+4)
  native: #01 pc 0000000000029544  /system/lib64/libc.so (ioctl+136)
  native: #02 pc 000000000001e22c  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::talkWithDriver(bool)+240)
  native: #03 pc 000000000001e884  /system/lib64/libhwbinder.so (android::hardware::IPCThreadState::waitForResponse(android::hardware::Parcel*, int*)+324)
  native: #04 pc 0000000000012204  /system/lib64/libhwbinder.so (android::hardware::BpHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+312)
  native: #05 pc 00000000000c9764  /system/lib64/android.hardware.gnss@1.0.so (android::hardware::gnss::V1_0::BpHwGnssXtra::_hidl_injectXtraData(android::hardware::IInterface*, android::hardware::details::HidlInstrumentor*, android::hardware::hidl_string const&)+244)
  native: #06 pc 000000000005d5c4  /system/lib64/libandroid_servers.so (android::android_location_GnssLocationProvider_inject_xtra_data(_JNIEnv*, _jobject*, _jbyteArray*, int)+268)
  at com.android.server.location.GnssLocationProvider.native_inject_xtra_data(Native method)
  at com.android.server.location.GnssLocationProvider.access$2300(GnssLocationProvider.java:112)
  at com.android.server.location.GnssLocationProvider$10.run(GnssLocationProvider.java:1140)
  at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1167)
  at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:641)
  at java.lang.Thread.run(Thread.java:764)
```
它在一个jni里执行一个hw binder call，结合下代码：
```c++
// frameworks/base/services/core/jni/com_android_server_location_GnssLocationProvider.cpp#1613
static void android_location_GnssLocationProvider_inject_xtra_data(JNIEnv* env, jobject /* obj */,
        jbyteArray data, jint length) {
    if (gnssXtraIface == nullptr) {
        ALOGE("XTRA Interface not supported");
        return;
    }
 
    jbyte* bytes = reinterpret_cast<jbyte *>(env->GetPrimitiveArrayCritical(data, 0));
    gnssXtraIface->injectXtraData(std::string((const char*)bytes, length));
    env->ReleasePrimitiveArrayCritical(data, bytes, JNI_ABORT);
}
```
（不熟悉art实现）一眼看过去，都是正常的jni调用，好像跟disable_flip_count没啥关系呀？全局搜一下DecrementDisableThreadFlip()和IncrementDisableThreadFlip被调用的地方：
```c++
ReleaseStringCritical() → DecrementDisableThreadFlip()
ReleasePrimitiveArray() → DecrementDisableThreadFlip()

GetPrimitiveArrayCritical() → IncrementDisableThreadFlip()
GetStringCritical() → IncrementDisableThreadFlip()
```

到这个地方，稍稍消化总结一下，不难推断出：
  这个问题必然是因为 AsyncTask #36709 在执行jni调用过程中，它执行了：
  GetPrimitiveArrayCritical() → IncrementDisableThreadFlip() → 使得全局变量 disable_thread_flip_count_ = 1
但是在继续执行 gnssXtraIface →injectXtraData() 这个 hal 接口的时候，一直被block，自然无法执行 ReleasePrimitiveArrayCritical() → DecrementDisableThreadFlip() → disable_thread_flip_count_ = 0


#### 4. gnssXtraIface→injectXtraData() 为什么会一直被block？
查看binder transactin日志
```bash
$ adb shell cat /sys/kernel/debug/binder/transactions
 
proc 1471
context hwbinder
  thread 1673: l 00 need_return 0 tr 0
    incoming transaction 979513688: ffffffed66132800 from 1007:1007 to 1471:1673 code 2 flags 10 pri 0:120 r1 node 978962390 size 48:0 data ffffff8014f00258
    outgoing transaction 979513687: ffffffed66133e00 from 1471:1673 to 1007:1007 code 3 flags 10 pri 0:120 r1
  thread 8981: l 01 need_return 0 tr 0
    incoming transaction 979513990: ffffffed2541c700 from 1007:2040 to 1471:8981 code 4 flags 10 pri 0:120 r1 node 978962390 size 132:16 data ffffff8014f00508
  thread 4738: l 00 need_return 0 tr 0
    outgoing transaction 979513850: ffffffee6324a400 from 1471:4738 to 1007:0 code 2 flags 10 pri 0:120 r1
  thread 8981: l 01 need_return 0 tr 0
    incoming transaction 979513990: ffffffed2541c700 from 1007:2040 to 1471:8981 code 4 flags 10 pri 0:120 r1 node 978962390 size 132:16 data ffffff8014f00508
 
proc 1007
context hwbinder8981
  thread 1007: l 12 need_return 0 tr 0
    outgoing transaction 979513688: ffffffed66132800 from 1007:1007 to 1471:1673 code 2 flags 10 pri 0:120 r1
    incoming transaction 979513687: ffffffed66133e00 from 1471:1673 to 1007:1007 code 3 flags 10 pri 0:120 r1 node 956 size 36:0 data ffffff8012000008
  thread 2040: l 10 need_return 0 tr 0
    outgoing transaction 979513990: ffffffed2541c700 from 1007:2040 to 1471:8981 code 4 flags 10 pri 0:120 r1
pending transaction 979513850: ffffffee6324a400 from 1471:4738 to 1007:0 code 2 flags 10 pri 0:120 r1 node 5700 size 120:16 data ffffff8012000030
```
incoming transaction from 1471:4738 to 1007:0，得到对端进程pid为1007， 继续看下这个进程里各个线程的状态
```bash
$ adb shell ps -T 1007
USER           PID   TID  PPID     VSZ    RSS WCHAN            ADDR S CMD           
system        1007  1007     1   29016    156 binder_thread_read  0 S ignss_1_1
system        1007  2040     1   29016    156 binder_thread_read  0 S IPC Thread
system        1007 17865     1   29016    156 poll_schedule_timeout 0 S ignss_1_1
```
各个线程看起来都是正常的，通过debuggerd查看backtrace
```c++
$ adb shell debuggerd -b 1007
----- pid 1007 at 2019-05-05 13:25:52 -----
Cmd line: /vendor/bin/ignss_1_1
ABI: 'arm64'
 
"ignss_1_1" sysTid=1007
  #00 pc 000000000006e5bc  /system/lib64/libc.so (__ioctl+4)
  #01 pc 0000000000029544  /system/lib64/libc.so (ioctl+136)
  #02 pc 000000000001e22c  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::talkWithDriver(bool)+240)
  #03 pc 000000000001e77c  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::waitForResponse(android::hardware::Parcel*, int*)+60)
  #04 pc 0000000000012204  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::BpHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+312)
  #05 pc 0000000000097ddc  /system/lib64/android.hardware.gnss@1.0.so (android::hardware::gnss::V1_0::BpHwGnssCallback::_hidl_gnssStatusCb(android::hardware::IInterface*, android::hardware::details::HidlInstrumentor*, android::hardware::gnss::V1_0::IGnssCallback::GnssStatusValue)+208)
  #06 pc 000000000001ccf0  /vendor/lib64/android.hardware.gnss@1.1-impl-xiaomi.so (android::hardware::gnss::V1_0::implementation::Gnss::statusCb(GpsStatus*)+68)
  #07 pc 000000000001b5b4  /vendor/lib64/hw/gps.brcm.so (gps_stop()+156)
  #08 pc 0000000000013ae0  /vendor/lib64/hw/gps.brcm.so (proxy__gps_stop()+168)
  #09 pc 000000000001e1d4  /vendor/lib64/android.hardware.gnss@1.1-impl-xiaomi.so (android::hardware::gnss::V1_0::implementation::Gnss::stop()+28)
  #10 pc 0000000000088328  /system/lib64/android.hardware.gnss@1.0.so (android::hardware::gnss::V1_0::BnHwGnss::_hidl_stop(android::hidl::base::V1_0::BnHwBase*, android::hardware::Parcel const&, android::hardware::Parcel*, std::__1::function<void (android::hardware::Parcel&)>)+152)
  #11 pc 000000000002e324  /system/lib64/android.hardware.gnss@1.1.so (android::hardware::gnss::V1_1::BnHwGnss::onTransact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+1624)
  #12 pc 000000000001df34  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::BHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+72)
  #13 pc 000000000001508c  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::executeCommand(int)+1508)
  #14 pc 0000000000014938  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::getAndExecuteCommand()+204)
  #15 pc 0000000000015708  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::joinThreadPool(bool)+268)
  #16 pc 0000000000000cb8  /vendor/bin/ignss_1_1 (main+468)
  #17 pc 00000000000acec0  /system/lib64/libc.so (__libc_init+88)
 
"IPC Thread" sysTid=2040
  #00 pc 000000000006e5bc  /system/lib64/libc.so (__ioctl+4)
  #01 pc 0000000000029544  /system/lib64/libc.so (ioctl+136)
  #02 pc 000000000001e22c  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::talkWithDriver(bool)+240)
  #03 pc 000000000001e884  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::IPCThreadState::waitForResponse(android::hardware::Parcel*, int*)+324)
  #04 pc 0000000000012204  /system/lib64/vndk-sp-28/libhwbinder.so (android::hardware::BpHwBinder::transact(unsigned int, android::hardware::Parcel const&, android::hardware::Parcel*, unsigned int, std::__1::function<void (android::hardware::Parcel&)>)+312)
  #05 pc 0000000000098294  /system/lib64/android.hardware.gnss@1.0.so (android::hardware::gnss::V1_0::BpHwGnssCallback::_hidl_gnssNmeaCb(android::hardware::IInterface*, android::hardware::details::HidlInstrumentor*, long, android::hardware::hidl_string const&)+272)
  #06 pc 000000000001d0b4  /vendor/lib64/android.hardware.gnss@1.1-impl-xiaomi.so (android::hardware::gnss::V1_0::implementation::Gnss::nmeaCb(long, char const*, int)+112)
  #07 pc 00000000000136d8  /vendor/lib64/hw/gps.brcm.so (proxy__gps_nmea_cb(long, char const*, int)+180)
  #08 pc 0000000000018c88  /vendor/lib64/hw/gps.brcm.so (GpsiClient::marshal_gps_nmea_cb(IpcIncomingMessage&)+300)
  #09 pc 00000000000252a4  /vendor/lib64/hw/gps.brcm.so (IpcPipeTransportBase::OnSelect(int, bool, bool, bool, void*)+344)
  #10 pc 0000000000025a28  /vendor/lib64/hw/gps.brcm.so (SelectManager::PerformOneWaitAndProcess()+468)
  #11 pc 0000000000017860  /vendor/lib64/hw/gps.brcm.so (ipc_thread_proc(void*)+56)
  #12 pc 0000000000023160  /vendor/lib64/android.hardware.gnss@1.1-impl-xiaomi.so (threadFunc(void*)+12)
  #13 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  #14 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
 
"ignss_1_1" sysTid=17865
  #00 pc 000000000006e604  /system/lib64/libc.so (__pselect6+4)
  #01 pc 000000000002bbf8  /system/lib64/libc.so (select+144)
  #02 pc 000000000001974c  /vendor/lib64/hw/flp.brcm.so (SelectManager::PerformOneWaitAndProcess()+268)
  #03 pc 000000000000e8e8  /vendor/lib64/hw/flp.brcm.so (ipc_thread_proc(void*)+116)
  #04 pc 0000000000081dac  /system/lib64/libc.so (__pthread_start(void*)+36)
  #05 pc 0000000000023788  /system/lib64/libc.so (__start_thread+68)
 
----- end 1007 -----
```
   
**结合上面的binder call日志，可以看到ignss_1_1进程内部的两个binder线程都在回调system_server进程的binder 接口，没有空闲binder线程可以处理来自system_server的gnssXtraIface→injectXtraData() 请求！**

incoming 1471:1673
outgoing 1007:1007 to 1471:1673  // blocked ! 
outgoing 1007:2040 to 1471:8981 // WaitingForGcThreadFlip  !

p.s. 1471:1673 并不是一个binder线程, 但确响应了来自1007:1007的binder call，这是binder api设计上面的优化，复用？ todo：确认

```java
"android.bg" prio=5 tid=13 Blocked
  | group="main" sCount=1 dsCount=0 flags=1 obj=0x13fc3428 self=0x7232239400
  | sysTid=1673 nice=0 cgrp=default sched=0/0 handle=0x721da8e4f0
  | state=S schedstat=( 19417818968810 14397831932031 20757829 ) utm=561393 stm=1380388 core=5 HZ=100
  | stack=0x721d98b000-0x721d98d000 stackSize=1041KB
  | held mutexes=
  at com.android.server.am.ActivityManagerService.broadcastIntent(ActivityManagerService.java:22705)
  - waiting to lock <0x00c6c1f5> (a com.android.server.am.ActivityManagerService) held by thread 146
  at android.app.ContextImpl.sendBroadcastAsUser(ContextImpl.java:1195)
  at com.android.server.location.GnssLocationProvider.reportStatus(GnssLocationProvider.java:1766)
  at com.android.server.location.GnssLocationProvider.native_stop(Native method)
  at com.android.server.location.GnssLocationProvider.stopNavigating(GnssLocationProvider.java:1607)
  at com.android.server.location.GnssLocationProvider.updateRequirements(GnssLocationProvider.java:1405)
  at com.android.server.location.GnssLocationProvider.handleSetRequest(GnssLocationProvider.java:1345)
  at com.android.server.location.GnssLocationProvider.access$4100(GnssLocationProvider.java:112)
  at com.android.server.location.GnssLocationProvider$ProviderHandler.handleMessage(GnssLocationProvider.java:2400)
  at android.os.Handler.dispatchMessage(Handler.java:106)
  at android.os.Looper.loop(Looper.java:207)
  at android.os.HandlerThread.run(HandlerThread.java:65)
```

#### 5. 修复方案
所以这个问题也是system_server↔ ignss_1_1 这两个进程相互binder call + jni call + 虚拟机正好在执行垃圾回收；

参考 [oracle的文档](https://docs.oracle.com/javase/7/docs/technotes/guides/jni/spec/functions.html):

After calling GetPrimitiveArrayCritical, the native code should not run for an extended period of time before it calls ReleasePrimitiveArrayCritical. We must treat the code inside this pair of functions as running in a "critical region." Inside a critical region, native code must not call other JNI functions, or any system call that may cause the current thread to block and wait for another Java thread. (For example, the current thread must not call read on a stream being written by another Java thread.)

These restrictions make it more likely that the native code will obtain an uncopied version of the array, even if the VM does not support pinning. For example, a VM may temporarily disable garbage collection when the native code is holding a pointer to an array obtained via GetPrimitiveArrayCritical.

GetPrimitiveArrayCritical 和 ReleasePrimitiveArrayCritical 两个函数间的代码执行耗时不应太久！ 结合此处的业务逻辑，而且也不会被太频繁的调用，拷贝一份原始数组给binder call作为参数即可：
```diff
static void android_location_GnssLocationProvider_inject_xtra_data(JNIEnv* env, jobject /* obj */,
        jbyteArray data, jint length) {
    if (gnssXtraIface == nullptr) {
        ALOGE("XTRA Interface not supported");
        return;
    }
 
--    jbyte* bytes = reinterpret_cast<jbyte *>(env->GetPrimitiveArrayCritical(data, 0));
++    jbyte* bytes = reinterpret_cast<jbyte *>(env->GetByteArrayElements(data, 0));
    gnssXtraIface->injectXtraData(std::string((const char*)bytes, length));
--    env->ReleasePrimitiveArrayCritical(data, bytes, JNI_ABORT);
++    env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
}
```
