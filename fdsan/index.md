# FdSanitizer 简介



## 背景
在分配file descriptors时, POSIX标准规定了内核必须从所有可被使用的fd数值中最小的一个, 参考[alloc_fd](http://opengrok.pt.xiaomi.com/opengrok2/s?refs=__alloc_fd&project=miui-q-aquila-dev)，如果代码里没有正确的处理好fd的open/close等操作，就可能会带来以下2个副作用：
- use-after-close
- double-close

<!-- more -->

示例: double-close问题
```cpp
void thread_one() {
    int fd = open("/dev/null", O_RDONLY);
    doWork(fd);
    close(fd);
}

void doWork(int fd) {
    doSomething();
    close(fd);
}

void thread_two() {
    int fd = open("log", O_WRONLY | O_APPEND);
    if (write(fd, "foo", 3) != 3) {
        err(1, "write failed!");
    }
}
```
上面的代码可能产生下面的行为，导致线程2写入失败：
```cpp
// 线程1                                   线程2
open("/dev/null", O_RDONLY) = 123
close(123) = 0 // during doWork()
                                          open("log", O_WRONLY | APPEND) = 123
close(123) = 0
                                          write(123, "foo", 3) = -1 (EBADF)
                                          err(1, "write failed!")
```

## Fd Sanitizer
Aosp在Android 10.0里，引入了一个fdsan机制，在发生前一节描述的异常行为时，可以选择让进程终止执行，并打印出发生错误线程的调用栈，这样开发者可以根据调用栈，快速了解出问题的模块，后面再去修正它。

先思考一个问题，设计一种检测前面的fd误操作问题的机制，需要考虑哪些东西？

1. api向前兼容
   不能修改libc已有的api
2. 鉴别一个fd的合法性
   我的fd真的是我的吗，我能使用它吗？
3. 友好的错误提示
   别人用了我的fd，或我用了别人的fd时，如何确认这个fd的拥有者？我们还需要backtrace！

###  double-close 或 use-after-close问题的本质

double-close和use-after-close本质上都是使用了一个已经被关闭的fd，只不过这里面有几种不同情况：
1. 线程1连续对同一个fd关闭2次，那么可能会因为EBADF而导致进程abort 
2. 线程1对同一个fd关闭了>=2次，而如果在第一次和第二次关闭期间，线程2此时刚刚打开一个文件或socket，那么
   就可能出现：线程1的第二次关闭的fd，正好等于线程2新打开的fd，而线程1的第二次关闭操作（意外）错误的把
   线程2创建的fd给关闭了，此后线程2如果对这个fd进行读写等操作就会失败
3. 线程1关闭了一个fd后，线程2立即新打开了一个fd，如果线程2新打开的fd对应的是一个结构化的文件，例如数据库文件、xml文件等，
   线程1意外的在关闭fd后，又尝试向这个fd写入数据，就有可能线程2操作的文件的结构被破坏！

我们可以看到问题的核心就是对fd的控制权(ownership)问题：
当我们对1个fd拥有控制权时，我们期望其别人不能对我们的fd进行操作，反过来也是，当一个fd的控制权在别人那时，也期望我们不会去操作他们的fd！

### unique_fd！

类似智能指针(unique_ptr)，用户代码里使用unique_fd，在各个函数间进行参数传递时，也是使用unique_fd来进行，而不是原先的传递raw fd，这样这个fd从open到close，都会有个唯一的unique_fd来标明它的控制权。

而且因为unique_fd**重载了operator int()**，所以它可以完美兼容已有的libc接口。

```cpp
class unique_fd_impl final {
public:
explicit unique_fd_impl(int fd) { reset(fd); }
~unique_fd_impl() { reset(); }

void reset(int new_value = -1) { reset(new_value, nullptr); }
void reset(int new_value, void* previous_tag) {
    int previous_errno = errno;

    if (fd_ != -1) {
        close(fd_, this);
    }

    fd_ = new_value;
    if (new_value != -1) {
        tag(new_value, previous_tag, this); // 对这个fd打tag，即声明控制权
    }
    errno = previous_errno;
}
    
static void Close(int fd, void* addr) {
      uint64_t tag = android_fdsan_create_owner_tag(ANDROID_FDSAN_OWNER_TYPE_UNIQUE_FD,
                                                    reinterpret_cast<uint64_t>(addr));
      android_fdsan_close_with_tag(fd, tag);
}

private:
    int fd_ = -1;
}

using unique_fd = unique_fd_impl<DefaultCloser>;
```
使用方式：
```cpp
#include <android-base/unique_fd.h>

void test(const char* path) {
    android::base::unique_fd fd(open(path, O_WRONLY));
    write(fd, "foo", 3);
    // close(fd); 无需手动关闭fd
}
```

下面先通过分析unique_fd的代码来一窥fdsan的检测原理：

```cpp
// bionic/libc/bionic/fdsan.cpp
static void tag(int fd, void* old_addr, void* new_addr) {
    uint64_t old_tag = android_fdsan_create_owner_tag(ANDROID_FDSAN_OWNER_TYPE_UNIQUE_FD,
                                                    reinterpret_cast<uint64_t>(old_addr));
    uint64_t new_tag = android_fdsan_create_owner_tag(ANDROID_FDSAN_OWNER_TYPE_UNIQUE_FD,
                                                    reinterpret_cast<uint64_t>(new_addr));
    android_fdsan_exchange_owner_tag(fd, old_tag, new_tag);
  }

uint64_t android_fdsan_create_owner_tag(android_fdsan_owner_type type, uint64_t tag) {
  if (tag == 0) {
    return 0;
  }
  // 高8位用于标记fd类型
  uint64_t result = static_cast<uint64_t>(type) << 56;
  // 即00000000,11111111,11111111,11111111,11111111,11111111,11111111,11111111
  uint64_t mask = (static_cast<uint64_t>(1) << 56) - 1;
  // 低56位用于标记fd的owner，若owner是unique_fd的话，参考前面的代码，可以知道即取unique_fd地址的低56位
  // note: 没有存地址的全部64位，是因为用户空间的变量地址，一般高8～16位一般都是0，
  // 高8位于是就可以用来下来存储type, 感兴趣的朋友可以看下linux的进程地址空间分布。
  result |= tag & mask;
  return result;
}


struct FdEntry {
  _Atomic(uint64_t) close_tag = 0;
};

void android_fdsan_exchange_owner_tag(int fd, uint64_t expected_tag, uint64_t new_tag) {
  FdEntry* fde = GetFdEntry(fd);
  if (!fde) {
    return;
  }

  uint64_t tag = expected_tag;
  if (!atomic_compare_exchange_strong(&fde->close_tag, &tag, new_tag)) {
    if (expected_tag && tag) {
      fdsan_error(
          "failed to exchange ownership of file descriptor: fd %d is "
          "owned by %s 0x%" PRIx64 ", was expected to be owned by %s 0x%" PRIx64,
          fd, android_fdsan_get_tag_type(tag), android_fdsan_get_tag_value(tag),
          android_fdsan_get_tag_type(expected_tag), android_fdsan_get_tag_value(expected_tag));
    } else if (expected_tag && !tag) {
      fdsan_error(
          "failed to exchange ownership of file descriptor: fd %d is "
          "unowned, was expected to be owned by %s 0x%" PRIx64,
          fd, android_fdsan_get_tag_type(expected_tag), android_fdsan_get_tag_value(expected_tag));
    } else if (!expected_tag && tag) {
      fdsan_error(
          "failed to exchange ownership of file descriptor: fd %d is "
          "owned by %s 0x%" PRIx64 ", was expected to be unowned",
          fd, android_fdsan_get_tag_type(tag), android_fdsan_get_tag_value(tag));
    }
  }
}
```
流程很简单，以上创建unique_fd时的tag操作系列调用，就是对fd控制权记录的检查和更新：
unique_fd创建的时候，对传入的参数fd进行检查，如果ownership不匹配，便会输出warning日志或abort（可配置）；
同样的，unique_fd销毁时，也会检查内部保存的fd的控制权是否依然还属于当前的unique_fd，如果是，则可以将其关闭；
如果控制权丢失了，那么通过fdsan_error打印相应的错误信息，并根据配置再采取是否需要终止当前进程的操作。

```cpp
// bionic/libc/bionic/fdsan.cpp
int android_fdsan_close_with_tag(int fd, uint64_t expected_tag) {
  FdEntry* fde = GetFdEntry(fd);
  if (!fde) {
    return ___close(fd);
  }

  uint64_t tag = expected_tag;
  if (!atomic_compare_exchange_strong(&fde->close_tag, &tag, 0)) {
    const char* expected_type = android_fdsan_get_tag_type(expected_tag);
    uint64_t expected_owner = android_fdsan_get_tag_value(expected_tag);
    const char* actual_type = android_fdsan_get_tag_type(tag);
    uint64_t actual_owner = android_fdsan_get_tag_value(tag);
    if (expected_tag && tag) {
      fdsan_error(
          "attempted to close file descriptor %d, "
          "expected to be owned by %s 0x%" PRIx64 ", actually owned by %s 0x%" PRIx64,
          fd, expected_type, expected_owner, actual_type, actual_owner);
    } else if (expected_tag && !tag) {
      fdsan_error(
          "attempted to close file descriptor %d, "
          "expected to be owned by %s 0x%" PRIx64 ", actually unowned",
          fd, expected_type, expected_owner);
    } else if (!expected_tag && tag) {
      fdsan_error(
          "attempted to close file descriptor %d, "
          "expected to be unowned, actually owned by %s 0x%" PRIx64,
          fd, actual_type, actual_owner);
    }
  }
  // 如果fd的控制权没有问题，就可以正常关闭这个fd了
  int rc = ___close(fd);
  // 而如果关闭fd时出错了，那这个fd要么一开始就不是一个合法的fd，或者它已经被关闭了
  if (expected_tag && rc == -1 && errno == EBADF) {
    fdsan_error("double-close of file descriptor %d detected", fd);
  }
  return rc;
}
```

通过分析以上的关键代码，可以发现fdsan本身是很简洁的，我们已经基本掌握了fdsan是如何通过unique_fd这个工具类来对fd控制权的创建和监控的。

### 自定义fd类型
自定义fd类型主要是为了便于详细区分不同模块间创建的fd，例如zip文件的fd，sqlite3的fd，java代码里的FileInputStream和FileOutputStream等，下面看一下这几类fd的控制权是如何创建和管理的。
####  zip类型的文件
```c++
// system/core/libziparchive/zip_archive.cc
ZipArchive::ZipArchive(const int fd, bool assume_ownership)
    : mapped_zip(fd),
      close_file(assume_ownership),
      directory_offset(0),
      central_directory(),
      directory_map(),
      num_entries(0),
      hash_table_size(0),
      hash_table(nullptr) {
  if (assume_ownership) { // 如果调用方明确了此fd由libzip自行管理
    android_fdsan_exchange_owner_tag(fd, 0, GetOwnerTag(this));
  }
}

uint64_t GetOwnerTag(const ZipArchive* archive) {
  return android_fdsan_create_owner_tag(ANDROID_FDSAN_OWNER_TYPE_ZIPARCHIVE,
                                        reinterpret_cast<uint64_t>(archive));
}

ZipArchive::~ZipArchive() {
  if (close_file && mapped_zip.GetFileDescriptor() >= 0) {
    android_fdsan_close_with_tag(mapped_zip.GetFileDescriptor(), GetOwnerTag(this));
  }

  free(hash_table);
}
```

###  数据库文件
```c++
// external/sqlite/dist/sqlite3.c
static int robust_open(const char *z, int f, mode_t m){
  int fd;
  mode_t m2 = m ? m : SQLITE_DEFAULT_FILE_PERMISSIONS;
  while(1){
#if defined(O_CLOEXEC)
    fd = osOpen(z,f|O_CLOEXEC,m2);
#else
    fd = osOpen(z,f,m2);
#endif
...
#if defined(__BIONIC__) && __ANDROID_API__ >= __ANDROID_API_Q__
    uint64_t tag = android_fdsan_create_owner_tag(
        ANDROID_FDSAN_OWNER_TYPE_SQLITE, fd);
    android_fdsan_exchange_owner_tag(fd, 0, tag);
#endif
  }
  return fd;
}

static void robust_close(unixFile *pFile, int h, int lineno){
#if defined(__BIONIC__) && __ANDROID_API__ >= __ANDROID_API_Q__
  uint64_t tag = android_fdsan_create_owner_tag(
      ANDROID_FDSAN_OWNER_TYPE_SQLITE, h);
  if( android_fdsan_close_with_tag(h, tag) ){
#else
  if( osClose(h) ){
#endif
    unixLogErrorAtLine(SQLITE_IOERR_CLOSE, "close",
                       pFile ? pFile->zPath : 0, lineno);
  }
}
```
### fopen/fclose

请参考bionic/libc/stdio/stdio.cpp#__FILE_close，不再详细描述

###  java代码里打开的fd

1. ParcelFileDescriptor

```java
public class ParcelFileDescriptor implements Parcelable, Closeable {
    ...
        public ParcelFileDescriptor(FileDescriptor fd, FileDescriptor commChannel) {
        mFd = fd;
        // 1. 通过jni调用前面的fdsan api设置这个fd的owner, 且将owner信息存储到FileDescriptor.ownerId变量里
        IoUtils.setFdOwner(mFd, this);
        ...
    }
    public void close() throws IOException {
        closeWithStatus(Status.OK, null);
    }

    private void closeWithStatus(int status, String msg) {
        if (mClosed) return;
        mClosed = true;
        if (mGuard != null) {
            mGuard.close();
        }
        // Status MUST be sent before closing actual descriptor
        writeCommStatusAndClose(status, msg);
        IoUtils.closeQuietly(mFd); // 2. 调用IoUtils工具类关闭这个fd
        releaseResources();
    }
}

public final class IoUtils {
    public static void close(FileDescriptor fd) throws IOException {
        IoBridge.closeAndSignalBlockedThreads(fd); // 3. 代理到IoBridge进行关闭
    }
    public static void setFdOwner(@NonNull FileDescriptor fd, @NonNull Object owner) {
        long previousOwnerId = fd.getOwnerId$();
        if (previousOwnerId != FileDescriptor.NO_OWNER) {
            throw new IllegalStateException("Attempted to take ownership of already-owned " +
                                            "FileDescriptor");
        }

        long ownerId = generateFdOwnerId(owner);
        fd.setOwnerId$(ownerId);

        // Set the file descriptor's owner ID, aborting if the previous value isn't as expected.
        Libcore.os.android_fdsan_exchange_owner_tag(fd, previousOwnerId, ownerId);
    }
}

public final class IoBridge {
    public static void closeAndSignalBlockedThreads(FileDescriptor fd) throws IOException {
        // fd is invalid after we call release.
        FileDescriptor oldFd = fd.release$();
        Libcore.os.close(oldFd); // Libcore.os.close实际由libcore.io.Linux.close这个native方法实现
    }
}
  ```
libcore.io.Linux.close方法的实现：
  ```cpp
// libcore/luni/src/main/native/libcore_io_Linux.cpp
static void Linux_close(JNIEnv* env, jobject, jobject javaFd) {
    // Get the FileDescriptor's 'fd' field and clear it.
    // We need to do this before we can throw an IOException (http://b/3222087).
    if (javaFd == nullptr) {
        jniThrowNullPointerException(env, "null fd");
        return;
    }
    int fd = jniGetFDFromFileDescriptor(env, javaFd);
    jniSetFileDescriptorOfFD(env, javaFd, -1);

    jlong ownerId = jniGetOwnerIdFromFileDescriptor(env, javaFd); // 通过jni获取到FileDescriptor.mOwnerId成员变量

    // Close with bionic's fd ownership tracking (which returns 0 in the case of EINTR).
    throwIfMinusOne(env, "close", android_fdsan_close_with_tag(fd, ownerId));
}
  ```
2. FileInputStream & FileOutputStream
   跟ParcelableFileDescriptor的实现类似，不再详述
3. PlainSocketImpl &  AbstractPlainDatagramSocketImpl
   略
4. RandomAccessFile
   略

## 如何查看进程的fdan记录
```bash
$ adb shell 
cepheus:/ # debuggerd `pidof system_server`
...
    fd 106: anon_inode:[eventfd] (owned by unique_fd 0x70c672a8f4)
    fd 107: anon_inode:[eventpoll] (owned by unique_fd 0x70c672a94c)
    fd 108: anon_inode:[eventpoll] (owned by unique_fd 0x70d027f6ec)
    fd 109: anon_inode:[eventfd] (owned by unique_fd 0x70c672c6b4)
    fd 110: anon_inode:[eventpoll] (owned by unique_fd 0x70c672c70c)
    fd 111: socket:[582031] (unowned)
    fd 112: anon_inode:[eventfd] (owned by unique_fd 0x70d027fa14)
    fd 113: anon_inode:[eventpoll] (owned by unique_fd 0x70d027fa6c)
    fd 114: /dev/cpuset/foreground/tasks (owned by unique_fd 0x70dd5a4ad0)
    fd 115: /system/priv-app/SettingsProvider/SettingsProvider.apk (owned by ZipArchive 0x70dd59f100)
    fd 116: anon_inode:[eventfd] (owned by unique_fd 0x70c672ca34)
    fd 117: anon_inode:[eventpoll] (owned by unique_fd 0x70c672ca8c)
    fd 118: /dev/ashmem (unowned)
...
```

## 如何启用fdsan

fdsan在Q上是默认启用的，只不过在遇到fd误操作问题时，预设的行为仅是打印一些警示日志。
比较让人高兴的是，fdsan也定义了不同的安全级别：

 - disabled：禁用
 - warn-once：只在第一次打印一条警告日志，并在/data/tombstone/目录下生成异常进程的调用栈
 - warn-always：跟warn-once一样，只不过每次出现fd误操作都会打印警告日志和生成tombstone文件
 - fatal：abort进程，并生成tombstone文件

fd也开放了对应的api可以让我们去调整一个进程在遇到此类异常时的行为：`android_fdsan_set_error_level` & `android_fdsan_get_error_level`，这样可以配置进程在遇到此类错误时，选择立即abort进程，并配置生成core文件，然后就可以愉快的去debug了！

## 兼容性问题

由于fdsan是在Q上libc里才引入的机制，对于Android旧版本是没有做支持的，而且我也check了一下20.0.5594570版的ndk，也没有把unique_fd工具类给开发出来，这对于系统开发人员到没有太大影响，但对于app开发，就需要自己实现一个unique_fd类，另外老版本Android系统上并没有这些fdsan api，我自己也写了一个[unique_fd_compat](https://github.com/wwm0609/unique_fd_compat)类，用来解决编译问题，仅供参考。

另外一个小tip：libc里预定义的fd owner类型比较少：
```c++
// bionic/libc/include/android/fdsan.h
enum android_fdsan_owner_type {
 ...
  /* android::base::unique_fd */
  ANDROID_FDSAN_OWNER_TYPE_UNIQUE_FD = 3,

  /* sqlite-owned file descriptors */
  ANDROID_FDSAN_OWNER_TYPE_SQLITE = 4,

  /* java.io.FileInputStream */
  ANDROID_FDSAN_OWNER_TYPE_FILEINPUTSTREAM = 5,

  /* java.io.FileOutputStream */
  ANDROID_FDSAN_OWNER_TYPE_FILEOUTPUTSTREAM = 6,

  /* java.io.RandomAccessFile */
  ANDROID_FDSAN_OWNER_TYPE_RANDOMACCESSFILE = 7,

  /* android.os.ParcelFileDescriptor */
  ANDROID_FDSAN_OWNER_TYPE_PARCELFILEDESCRIPTOR = 8,

  /* java.net.SocketImpl */
  ANDROID_FDSAN_OWNER_TYPE_SOCKETIMPL = 11,

  /* libziparchive's ZipArchive */
  ANDROID_FDSAN_OWNER_TYPE_ZIPARCHIVE = 12,
};
```
但从前面的分析，我们发现，其实它是可以支持到255个不同类型的，这样的话在我们自己实现的unique_fd里就可以做到支持不同模块设置不同的子类型，例如audio，video模块可以各自预设不同的子类型，以便于出现问题时快速区分。

## Aosp官方介绍

https://android.googlesource.com/platform/bionic/+/master/docs/fdsan.md


