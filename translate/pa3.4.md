[#](#Simple-file-system) simple file system
===================

To implement a complete batch system, we need to provide multiple programs to the system. We have previously stored our programs as files on the ramdisk, but if the number of programs increases, we need to know the position (offset) of certain program in ramdisk. Our ramdisk already provides a read/write interface, which makes it easy to access the contents of a certain location, which doesn't seem to be much of a problem for Nanos-lite; on the other hand, user programs need to process data, and the data they process may be organized into files, so how does the user program know where the files are located on the ramdisk? Moreover, files are dynamically added and deleted without the user program's knowledge. This means that it is not feasible to make the ramdisk read/write interface directly available to the user program. The operating system needs to provide the user program with a higher level of abstraction over the storage medium driver, that is, the file.

A file is essentially a sequence of bytes, with some additional attributes. Here, we will discuss files in the normal sense. Thus, those additional attributes maintain a mapping of files to ramdisk storage locations. In order to manage these mappings and provide an interface to the upper layers for file operations, we need to implement a file system in Nanos-lite.

Don't be intimidated by the word "file system", our needs for a file system are not that complex, so we can define a simple file system sfs (Simple File System):

*   The size of each file is fixed
*   Writing a file is not allowed to exceed the size of the original file
*   The number of files is fixed, no new files can be created
*   No directories

Since the number and size of files is fixed, it is natural to fix each file in a separate location on the ramdisk. These simplifications make the file system much less difficult to implement. Of course, real filesystems are much more complex than sfs.

Let's assume that the files are stored one by one from the very beginning of the ramdisk.

    0
    +-------------+---------+----------+-----------+--
    |    file0    |  file1  |  ......  |   filen   |
    +-------------+---------+----------+-----------+--
     \           / \       /            \         /
      +  size0  +   +size1+              + sizen +
    

In order to keep track of the names and sizes of the files in the ramdisk, we also need a "file list". Nanos-lite's Makefile already provides a script to maintain this information, so make the following changes to `nanos-lite/Makefile`.

    --- nanos-lite/Makefile
    +++ nanos-lite/Makefile
    @@ -1,2 +1,2 @@
    -#HAS_NAVY = 1
    +HAS_NAVY = 1
     RAMDISK_FILE = build/ramdisk.img
    

Then running `make ARCH=$ISA-nemu update` will automatically compile the program in Navy, and assemble everything in the `navy-apps/fsimg/` directory into a ramdisk image `navy-apps/build/ramdisk.img`, and generate a file list `navy-apps/build/ramdisk.h` for the ramdisk image, which Nanos-lite's `Makefile` will link to the project via a soft link.

#### Remember to update the image file

If you have modified the contents of Navy, please remember to update the image file with the above command.

The "file list" is actually an array, and each element of the array is a structure.

    typedef struct {
      char *name;         // File name
      size_t size;        // File size
      size_t disk_offset;  // File offset in ramdisk
    } Finfo;
    

In sfs, all three pieces of information are fixed. The filenames are not as we normally use them: since sfs does not have directories, we consider the directory separator `/` to be part of the filename, e.g., `/bin/hello` is a full filename. This approach also implies a hierarchy of directories, which is simple and effective when the number of files is small.

With this information, the most basic file reading and writing operations can be realized:

    size_t read(const char *filename, void *buf, size_t len);
    size_t write(const char *filename, const void *buf, size_t len);
    

In real operating systems, however, this direct use of file names as parameters for read and write operations has its drawbacks. For example, when browsing a file with the `less` tool.

    cat file | less
    

The `cat` tool wants to write the contents of the file to the `less` tool's standard input, but we can't identify the `less` tool's standard input with the name of the file! In fact, there are quite a few "unnamed" files in the operating system. In order to manage them in a uniform way, we would like to represent the file by a number, which is a file descriptor. A file descriptor corresponds to a file that is being opened, and it is up to the operating system to maintain the mapping of file descriptors to specific files. It is natural to open a file with the `open()` system call, which returns the corresponding file descriptor.

    int open(const char *pathname, int flags, int mode);
    

In Nanos-lite, since the number of files in the sfs is fixed, we can simply return the subscripts of the file list to the user program as the file descriptors of the corresponding files. From now on, all file operations identify files by their file descriptors.

    size_t read(int fd, void *buf, size_t len);
    size_t write(int fd, const void *buf, size_t len);
    int close(int fd);
    

Also, we don't want to have to start from scratch every time we read or write to a file. So we need to introduce an offset attribute, `open_offset`, for each open file to keep track of where the file operation is currently taking place. Each time a file is read or written, the offset is advanced by a certain number of bytes.

#### File Offsets and User Programs

In fact, in a real operating system, maintaining offsets in a file record table can cause a user program to fail to perform certain functions. Explaining this requires some knowledge beyond the scope of this course, so we won't go into it here. You can think about this in your operating systems course.

Since Nanos-lite is a stripped-down version of the operating system, the above problem will not occur for a while, but for simplicity of implementation, we will maintain the offsets in a file record table.

The offsets can be adjusted by the `lseek()` system call, which allows you to read or write anywhere in the file: `lseek()`:

    size_t lseek(int fd, size_t offset, int whence);
    

In order to facilitate standard input and output for user programs, the operating system has prepared three default file descriptors:

    #define FD_STDIN 0
    #define FD_STDOUT 1
    #define FD_STDERR 2
    

They correspond to standard input `stdin`, standard output `stdout` and standard error `stderr`. We often use printf, which will eventually call `write(FD_STDOUT, buf, len)` for output, and scanf, which will call `read(FD_STDIN, buf, len)` for read.

The `file_table` defined in `nanos-lite/src/fs.c` will contain `nanos-lite/src/files.h`, which will be preceded by placeholder entries for three special files: `stdin`, `stdout`, and `stderr`, which are there to ensure that the sfs is in line with the agreed-upon standard. For example, the file descriptor for `stdout` is `1` by convention, and by adding the three placeholder entries, the `1` subscript in the file record table will not be assigned to any other common file.

Based on the above information, we can implement the following file operations in the file system:

    int fs_open(const char *pathname, int flags, int mode);
    size_t fs_read(int fd, void *buf, size_t len);
    size_t fs_write(int fd, const void *buf, size_t len);
    size_t fs_lseek(int fd, size_t offset, int whence);
    int fs_close(int fd);
    

These file operations are actually implementations of the corresponding system calls in the kernel. You can find out what they do via `man`, for example

    man 2 open
    

where `2` means consulting the manual page associated with the system call. Implement these file operations with the following in mind:

*   Since every file in sfs is fixed and no new files are created, "`fs_open()` did not find the file indicated by `pathname`" is an exception, and you need to terminate the program with an assertion.
*   To simplify the implementation, we allow all user programs to read and write to all existing files, so that in the future, we can ignore `flags` and `mode` when implementing `fs_open()`.
*   Use `ramdisk_read()` and `ramdisk_write()` to actually read and write files.
*   Since the size of the file is fixed, when implementing `fs_read()`, `fs_write()` and `fs_lseek()`, be careful that the offsets do not cross the file boundaries.
*   Except for writing to `stdout` and `stderr` (using `putch()` to output to the serial port), the rest of the operations on the three special files `stdin`, `stdout` and `stderr` can be ignored.
*   Since sfs does not maintain the status of open files, `fs_close()` can simply return `0`, indicating that the close was always successful.

Finally, you need to add system calls to Nanos-lite and Navy's libos to invoke the appropriate file operations.

#### Let loader use files

Previously, we had the loader call `ramdisk_read()` directly to load the user program. As the number of files in the ramdisk grows, this approach is no longer appropriate, and we need to give the loader the benefit of the filesystem in the first place.

You need to implement `fs_open()`, `fs_read()` and `fs_close()`, so that you can specify the loaded program in the loader with a filename, e.g. "/bin/hello".

Once this is implemented, changing the user program in the future will only require changing the filename passed to the `naive_uload()` function.

#### Implementing a complete file system

Implement `fs_write()` and `fs_lseek()`, then run the test program `navy-apps/tests/file-test`. In order to compile it, you need to add it to the `TESTS` variable of `navy-apps/Makefile`, so that it will eventually be included in the ramdisk image. This test program is used to perform some simple file reading, writing and positioning operations. If your implementation is correct, you will see the program output the `PASS!!!` message.

#### Remember to update the app list

If you wish to add an application to the image, please remember to add it to the list of applications in the Makefile above.

#### Support strace for sfs

Due to the feature of sfs, opening the same file will always return the same file descriptor. This means that we can translate the file descriptors in strace directly into filenames to get a more readable trace. Try to implement this feature, it will help you to use strace in the future.

[#](#Everything-is-a-file) Everything is a file
-----------------

The IOEs in AM show us what a program needs to do with input and output. So on Nanos-lite, what does a user program do if it wants to access a device? One of the most straightforward ways to do this is to have the operating system provide a separate system call for each device, which allows the user program to access the functionality directly through these system calls. However, there are a number of problems with this approach:

*   First of all, there are various types of devices, and their functions are even more numerous, to implement system calls for each of them to provide interfaces to the user program, itself already lacks feasibility.
*   In addition, since the functions of devices vary greatly, if the interfaces provided are not uniform, the interaction between programs and devices becomes difficult. Therefore, we need a way to abstract the functions of devices and provide a unified interface to user programs.

As we mentioned before, the essence of a file is a sequence of bytes. In fact, computer systems are full of byte sequences (what would a computer do with an unordered collection of bytes?) , and we can easily give many examples: we can use bytes in a file, and we can use bytes in a file in a file. , we can easily give many examples.

*   Memory is byte-addressed, which is naturally a sequence of bytes, so our previous use of ramdisk as a sequence of bytes is even more obvious
*   A pipe (`|` in shell commands) is a first-in-first-out sequence of bytes, which is essentially a queue buffer in memory
*   The disk can also be viewed as a byte sequence: we can number each byte on the disk, for example, the nth byte of the xth pillar, the yth head, the zth sector, all the bytes on the disk in accordance with the number of the size of the arrangement, you get a sequence of bytes
*   Network socket is also a kind of byte sequence, it has a buffer, responsible for storing the received network packets, the upper layer application sees the contents of the socket as a byte sequence, and handles them through some special file operations. We introduced DiffTest in PA2, if you RTFSC, you will find that the `qemu-diff` is to communicate with QEMU through socket, and the way to manipulate the socket is `fgetc()` and `fputc()`
*   Some information about the operating system can be exposed to the user as a sequence of bytes, such as CPU configuration information
*   Special features provided by the operating system, such as the random number generator, can also be viewed as an infinitely long sequence of bytes
*   Even some non-storage types of hardware can be viewed as sequences of bytes: the encoding of the keys we hit in sequence on a keyboard forms a sequence of bytes, and the content of each pixel on a display can be viewed as a sequence of bytes in the order in which it is displayed...

Since a file is a sequence of bytes, it's only natural that all these various sequences of bytes should be considered files. Unix does this, hence the phrase "everything is a file". The most intuitive benefit of this approach is that it provides a uniform interface to different things: we can use the file interface to manipulate everything on the computer without having to make detailed distinctions: for example, the `ramdisk` rule in `navy-apps/Makefile` pipes the input and output of various shell utilities to produce a file list

    wc -c $(FSIMG_FILES) | grep -v 'total$$' | sed -e 's+ ./fsimg+ +' |
      awk -v sum=0 '{print "\x7b\x22" $$2 "\x22\x2c " $$1 "\x2c " sum "\x7d\x2c";sum += $$1}' >> $(RAMDISK_H)
    

Viewing the contents of a disk in hexadecimal format

    head -c 512 /dev/sda | hd
    

查看CPU是否有Spectre漏洞Check CPU for Spectre vulnerabilities

    cat /proc/cpuinfo | grep 'spectre'
    

Even the "Little Star" sample audio we provided in PA2 was violently spliced together through simple file manipulation.

    cat Do.ogg Do.ogg So.ogg So.ogg La.ogg La.ogg So.ogg > little-star.ogg
    

As well as

    #include "/dev/urandom"
    

The contents of the random device will be included in the source file: since the random device is an infinite sequence of bytes, submitting the source file of a program containing the above contents will crash some Online Judge platforms that do not have strong detection capabilities.

The "everything is a file" abstraction makes it easy to do things with standard tools that are not easy to do on Windows, and this is part of the Unix philosophy: each program uses text files as input and output, which makes it easy for programs to work together. GNU/Linux inherits from Unix, and naturally inherits this excellent feature. In order to provide a uniform abstraction for user programs, Nanos-lite also attempts to abstract IOEs to files.

### [#](#Virtual-file-system) Virtual file system

In order to realize the idea that everything is a file, we need to extend our previous implementation of file operations: not only do we need to be able to read and write normal files, but we also need to be able to support all kinds of "special file" operations. The way to do this, as you're all too familiar with, is abstraction!

We extend the semantics of our previously implemented file manipulation APIs to support arbitrary files (including "special files"):

    int fs_open(const char *pathname, int flags, int mode);
    size_t fs_read(int fd, void *buf, size_t len);
    size_t fs_write(int fd, const void *buf, size_t len);
    size_t fs_lseek(int fd, size_t offset, int whence);
    int fs_close(int fd);
    

The extended semantics of this API have a cool name, called [VFS (Virtual File System)](https://en.wikipedia.org/wiki/Virtual_file_system). Since there is a virtual filesystem, there should also be a "real filesystem", where the real filesystem refers to how a certain type of file is manipulated. For example, on Nanos-lite, ordinary files are manipulated through the ramdisk API; on real operating systems, there are countless types of real filesystems: for example, if you're familiar with Windows, you'll know NTFS, which manages ordinary files, and EXT4, which is currently more popular on GNU/Linux; and there are even more types of special files. As for special files, there are many more, so there are `procfs`, `tmpfs`, `devfs`, `sysfs`, `initramfs`... These are different real filesystems, each of which implements a specific way of manipulating these files.

So, VFS is actually an abstraction of different kinds of real file systems, it uses a set of APIs to describe the abstract behavior of these real file systems, blocking the differences between the real file systems, the upper modules (such as system call handler) do not have to care about the current operation of the file is what type, as long as the call to this set of APIs can be completed to the appropriate file operations. With the concept of VFS, it is very easy to add a real file system: just wrap the real file system access method into the VFS API, the upper module does not need to change any code, it can support a new real file system.

#### Here it comes again

When reading the above text, if you think of the concept of AM, you are right, because the idea behind VFS is also abstraction.

In Nanos-lite, the key to implementing VFS is the two read/write function pointers in the `Finfo` structure:

    typedef struct {
      char *name;         // File name
      size_t size;        // File size
      size_t disk_offset;  // File offset in ramdisk
      ReadFn read;        // Read function pointer
      WriteFn write;      // Write function pointer
    } Finfo;
    

Among them, `ReadFn` and `WriteFn` are two kinds of function pointers, which are used to point to the function that actually reads or writes and returns the number of bytes successfully read or written. With these two function pointers, we only need to set up different read/write functions for different files in the file record table, and then we can call the specific read/write functions by `f->read()` and `f->write()`.

#### Simulating Object-Oriented Programming in C

The implementation of VFS shows how to simulate some of the basic concepts of object-oriented programming in C: for example, the definition of a class through a structure, ordinary variables in the structure can be regarded as members of the class, function pointers can be regarded as methods of the class, and different functions can be set to function pointers to realize the overloading of methods...

This suggests that the seemingly nebulous concepts of OOP are no more advanced than in C. It's just that the OOP compiler does more for us, and after compiling into machine code, OOP doesn't exist. [Object-Oriented Programming With ANSI-C](https://www.cs.rit.edu/~ats/books/ooc.pdf) This book is dedicated to simulating OOP concepts and functionality using ANSI-C. There are many places in the GNU/Linux kernel code where OOP is present.

However, in Nanos-lite, since the number of special files is very small, we assume that when the above function pointer is `NULL`, it means that the corresponding file is a normal file, which is read/written by the ramdisk API, so that we don't need to explicitly specify the ramdisk read/write functions for most normal files.

We think of a file as a sequence of bytes, most byte sequences are "static", e.g., for ramdisk and files on disk, if we don't modify them, they will always be located in the same place, such byte sequences have the concept of "location"; but there are some special byte sequences that are not, e.g., byte sequences of typed keys are "flowing", after being read out, such byte sequences will not exist. However, there are some special byte sequences which are not like that, for example, byte sequences typed into a key are "flowing", and after they are read out they don't exist anymore. Files belonging to the former category support the `lseek` operation, and the devices that store them are called "block devices"; files belonging to the latter category do not support the `lseek` operation, and the corresponding devices are called "character devices". Real operating systems also abstract from the `lseek` operation, which we have simplified in Nanos-lite by not implementing it.

### [#](#IOE-for-operating-system) IOE for operating system

With VFS, it is very easy to abstract IOEs into files.

The first place to start is, of course, the simplest output device: the serial port. In Nanos-lite, both `stdout` and `stderr` are output to the serial port. Previously you might have been able to determine whether `sys_write()` writes to the serial port by determining whether `fd` is `1` or `2`. Now with VFS, we don't need to let the system call handler care about these special files: we just need to implement `serial_write()` in `nanos-lite/src/device.c`, and then set up the appropriate write function in the file record table to accomplish the above. Since the serial port is a character device, the corresponding byte sequence has no concept of "position", so the `offset` parameter in `serial_write()` can be ignored. In addition, Nanos-lite is not intended to support `stdin` reads, so it is sufficient to set the error function in the file log table.

#### Abstracting the serial port to a file

Based on the above, let's make the VFS support writing to the serial port.

Regarding the input devices, let's take a look at the clock first. The clock is unique in that most operating systems do not abstract it into a file, but instead provide clock-related system calls for the user program to access. In Nanos-lite, we also provide a `SYS_gettimeofday` system call, which allows the user program to read out the current system time.

#### Implement gettimeofday

Implement the `gettimeofday` system call, please RTFM for the meaning of the parameters of this system call. After implementation, add a new `timer-test` test in `navy-apps/tests/`, and get the current time by `gettimeofday()`, and output a sentence every 0.5 seconds.

In order to better encapsulate the IOE functionality, we provide a multimedia library called NDL (NJU DirectMedia Layer) in Navy. The code for this library is located in `navy-apps/libs/libndl/NDL.c`, but most of the functionality is not implemented. There are a few things in the code related to `NWM_APP` that you can ignore for now, but don't modify the code, as you will experience the functionality at the end of PA4. The NDL provides the user with a clock-related API:

    // Returns the system time in milliseconds
    uint32_t NDL_GetTicks();
    

#### 实现NDL的时钟

你需要用`gettimeofday()`实现`NDL_GetTicks()`, 然后修改`timer-test`测试, 让它通过调用`NDL_GetTicks()`来获取当前时间. 你可以根据需要在`NDL_Init()`和`NDL_Quit()`中添加初始化代码和结束代码, 我们约定程序在使用NDL库的功能之前必须先调用`NDL_Init()`. 如果你认为无需添加初始化代码, 则无需改动它们.

另一个输入设备是键盘, 按键信息对系统来说本质上就是到来了一个事件. 一种简单的方式是把事件以文本的形式表现出来, 我们定义以下两种事件,

*   按下按键事件, 如`kd RETURN`表示按下回车键
*   松开按键事件, 如`ku A`表示松开`A`键

按键名称与AM中的定义的按键名相同, 均为大写. 此外, 一个事件以换行符`\n`结束.

我们采用文本形式来描述事件有两个好处, 首先文本显然是一种字节序列, 这使得事件很容易抽象成文件; 此外文本方式使得用户程序可以容易可读地解析事件的内容. Nanos-lite和Navy约定, 上述事件抽象成一个特殊文件`/dev/events`, 它需要支持读操作, 用户程序可以从中读出按键事件, 但它不必支持`lseek`, 因为它是一个字符设备.

NDL向用户提供了一个和按键事件相关的API:

    // 读出一条事件信息, 将其写入`buf`中, 最长写入`len`字节
    // 若读出了有效的事件, 函数返回1, 否则返回0
    int NDL_PollEvent(char *buf, int len);
    

#### 把按键输入抽象成文件

你需要:

*   实现`events_read()`(在`nanos-lite/src/device.c`中定义), 把事件写入到`buf`中, 最长写入`len`字节, 然后返回写入的实际长度. 其中按键名已经在字符串数组`names`中定义好了, 你需要借助IOE的API来获得设备的输入. 另外, 若当前没有有效按键, 则返回0即可.
*   在VFS中添加对`/dev/events`的支持.
*   在NDL中实现`NDL_PollEvent()`, 从`/dev/events`中读出事件并写入到`buf`中.

我们可以假设一次最多只会读出一个事件, 这样可以简化你的实现. 实现后, 让Nanos-lite运行`navy-apps/tests/event-test`, 如果实现正确, 敲击按键时程序会输出按键事件的信息.

#### 用fopen()还是open()?

这是个非常值得思考的问题. 你需要思考这两组API具体行为的区别, 然后分析`/dev/events`这个特殊文件应该用哪种函数来操作. 我们已经在某一个蓝色信息框中给出一些提示了.

最后是VGA, 程序为了更新屏幕, 只需要将像素信息写入VGA的显存即可. 于是, Nanos-lite需要做的, 便是把显存抽象成文件. 显存本身也是一段存储空间, 它以行优先的方式存储了将要在屏幕上显示的像素. Nanos-lite和Navy约定, 把显存抽象成文件`/dev/fb`(fb为frame buffer之意), 它需要支持写操作和`lseek`, 以便于把像素更新到屏幕的指定位置上.

NDL向用户提供了两个和绘制屏幕相关的API:

    // 打开一张(*w) X (*h)的画布
    // 如果*w和*h均为0, 则将系统全屏幕作为画布, 并将*w和*h分别设为系统屏幕的大小
    void NDL_OpenCanvas(int *w, int *h);
    
    // 向画布`(x, y)`坐标处绘制`w*h`的矩形图像, 并将该绘制区域同步到屏幕上
    // 图像像素按行优先方式存储在`pixels`中, 每个像素用32位整数以`00RRGGBB`的方式描述颜色
    void NDL_DrawRect(uint32_t *pixels, int x, int y, int w, int h);
    

其中"画布"是一个面向程序的概念, 程序绘图时的坐标都是针对画布来设定的, 这样程序就无需关心系统屏幕的大小, 以及需要将图像绘制到系统屏幕的哪一个位置. NDL可以根据系统屏幕大小以及画布大小, 来决定将画布"贴"到哪里, 例如贴到屏幕左上角或者居中, 从而将画布的内容写入到frame buffer中正确的位置.

`NDL_DrawRect()`的功能和PA2中介绍的绘图接口是非常类似的. 但为了实现它, NDL还需要知道屏幕大小的信息. Nanos-lite和Navy约定, 屏幕大小的信息通过`/proc/dispinfo`文件来获得, 它需要支持读操作. `navy-apps/README.md`中对这个文件内容的格式进行了约定, 你需要阅读它. 至于具体的屏幕大小, 你需要通过IOE的相应API来获取.

#### 在NDL中获取屏幕大小

*   实现`dispinfo_read()`(在`nanos-lite/src/device.c`中定义), 按照约定将文件的`len`字节写到`buf`中(我们认为这个文件不支持`lseek`, 可忽略`offset`).
*   在NDL中读出这个文件的内容, 从中解析出屏幕大小, 然后实现`NDL_OpenCanvas()`的功能. 目前`NDL_OpenCanvas()`只需要记录画布的大小就可以了, 当然我们要求画布大小不能超过屏幕大小.

让Nanos-lite运行`navy-apps/tests/bmp-test`, 由于目前还没有实现绘图功能, 因此无法输出图像内容, 但你可以先通过`printf()`输出解析出的屏幕大小.

#### 把VGA显存抽象成文件

*   在`init_fs()`(在`nanos-lite/src/fs.c`中定义)中对文件记录表中`/dev/fb`的大小进行初始化.
*   实现`fb_write()`(在`nanos-lite/src/device.c`中定义), 用于把`buf`中的`len`字节写到屏幕上`offset`处. 你需要先从`offset`计算出屏幕上的坐标, 然后调用IOE来进行绘图. 另外我们约定每次绘图后总是马上将frame buffer中的内容同步到屏幕上.
*   在NDL中实现`NDL_DrawRect()`, 通过往`/dev/fb`中的正确位置写入像素信息来绘制图像. 你需要梳理清楚系统屏幕(即frame buffer), `NDL_OpenCanvas()`打开的画布, 以及`NDL_DrawRect()`指示的绘制区域之间的位置关系.

让Nanos-lite运行`navy-apps/tests/bmp-test`, 如果实现正确, 你将会看到屏幕上显示Project-N的logo.

#### 实现居中的画布

你可以根据屏幕大小和画布大小, 让NDL将图像绘制到屏幕的中央, 从而获得较好的视觉效果.