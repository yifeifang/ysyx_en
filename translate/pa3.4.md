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

#### 让loader使用文件

我们之前是让loader来直接调用`ramdisk_read()`来加载用户程序. ramdisk中的文件数量增加之后, 这种方式就不合适了, 我们首先需要让loader享受到文件系统的便利.

你需要先实现`fs_open()`, `fs_read()`和`fs_close()`, 这样就可以在loader中使用文件名来指定加载的程序了, 例如"/bin/hello".

实现之后, 以后更换用户程序只需要修改传入`naive_uload()`函数的文件名即可.

#### 实现完整的文件系统

实现`fs_write()`和`fs_lseek()`, 然后运行测试程序`navy-apps/tests/file-test`. 为了编译它, 你需要把它加到`navy-apps/Makefile`的`TESTS`变量中, 这样它最终就会被包含在ramdisk镜像中. 这个测试程序用于进行一些简单的文件读写和定位操作. 如果你的实现正确, 你将会看到程序输出`PASS!!!`的信息.

#### 记得更新应用程序列表

如果你希望在镜像中添加一个应用程序, 请记得将它加入到上述Makefile文件的应用程序列表中.

#### 支持sfs的strace

由于sfs的特性, 打开同一个文件总是会返回相同的文件描述符. 这意味着, 我们可以把strace中的文件描述符直接翻译成文件名, 得到可读性更好的trace信息. 尝试实现这一功能, 它可以为你将来使用strace提供一些便利.

[#](#一切皆文件) 一切皆文件
-----------------

AM中的IOE向我们展现了程序进行输入输出的需求. 那么在Nanos-lite上, 如果用户程序想访问设备, 要怎么办呢? 一种最直接的方式, 就是让操作系统为每个设备单独提供一个系统调用, 用户程序通过这些系统调用, 就可以直接使用相应的功能了. 然而这种做法却存在不少问题:

*   首先, 设备的类型五花八门, 其功能更是数不胜数, 要为它们分别实现系统调用来给用户程序提供接口, 本身就已经缺乏可行性了;
*   此外, 由于设备的功能差别较大, 若提供的接口不能统一, 程序和设备之间的交互就会变得困难. 所以我们需要有一种方式对设备的功能进行抽象, 向用户程序提供统一的接口.

我们之前提到, 文件的本质就是字节序列. 事实上, 计算机系统中到处都是字节序列(如果只是无序的字节集合, 计算机要如何处理?), 我们可以轻松地举出很多例子:

*   内存是以字节编址的, 天然就是一个字节序列, 因而我们之前使用的ramdisk作为字节序列也更加显而易见了
*   管道(shell命令中的`|`)是一种先进先出的字节序列, 本质上它是内存中的一个队列缓冲区
*   磁盘也可以看成一个字节序列: 我们可以为磁盘上的每一个字节进行编号, 例如第x柱面第y磁头第z扇区中的第n字节, 把磁盘上的所有字节按照编号的大小进行排列, 便得到了一个字节序列
*   socket(网络套接字)也是一种字节序列, 它有一个缓冲区, 负责存放接收到的网络数据包, 上层应用将socket中的内容看做是字节序列, 并通过一些特殊的文件操作来处理它们. 我们在PA2中介绍了DiffTest, 如果你RTFSC, 就会发现其中的`qemu-diff`就是通过socket与QEMU进行通信的, 而操作socket的方式就是`fgetc()`和`fputc()`
*   操作系统的一些信息可以以字节序列的方式暴露给用户, 例如CPU的配置信息
*   操作系统提供的一些特殊的功能, 如随机数生成器, 也可以看成一个无穷长的字节序列
*   甚至一些非存储类型的硬件也可以看成是字节序列: 我们在键盘上按顺序敲入按键的编码形成了一个字节序列, 显示器上每一个像素的内容按照其顺序也可以看做是字节序列...

既然文件就是字节序列, 那很自然地, 上面这些五花八门的字节序列应该都可以看成文件. Unix就是这样做的, 因此有"一切皆文件"(Everything is a file)的说法. 这种做法最直观的好处就是为不同的事物提供了统一的接口: 我们可以使用文件的接口来操作计算机上的一切, 而不必对它们进行详细的区分: 例如 `navy-apps/Makefile`的`ramdisk`规则通过管道把各个shell工具的输入输出连起来, 生成文件记录表

    wc -c $(FSIMG_FILES) | grep -v 'total$$' | sed -e 's+ ./fsimg+ +' |
      awk -v sum=0 '{print "\x7b\x22" $$2 "\x22\x2c " $$1 "\x2c " sum "\x7d\x2c";sum += $$1}' >> $(RAMDISK_H)
    

以十六进制的方式查看磁盘上的内容

    head -c 512 /dev/sda | hd
    

查看CPU是否有Spectre漏洞

    cat /proc/cpuinfo | grep 'spectre'
    

甚至我们在PA2中提供的"小星星"示例音频, 也是通过简单的文件操作暴力拼接而成的

    cat Do.ogg Do.ogg So.ogg So.ogg La.ogg La.ogg So.ogg > little-star.ogg
    

而

    #include "/dev/urandom"
    

则会将urandom设备中的内容包含到源文件中: 由于urandom设备是一个长度无穷的字节序列, 提交一个包含上述内容的程序源文件将会令一些检测功能不强的Online Judge平台直接崩溃.

"一切皆文件"的抽象使得我们可以通过标准工具很容易完成一些在Windows下不易完成的工作, 这其实体现了Unix哲学的部分内容: 每个程序采用文本文件作为输入输出, 这样可以使程序之间易于合作. GNU/Linux继承自Unix, 也自然继承了这种优秀的特性. 为了向用户程序提供统一的抽象, Nanos-lite也尝试将IOE抽象成文件.

### [#](#虚拟文件系统) 虚拟文件系统

为了实现一切皆文件的思想, 我们之前实现的文件操作就需要进行扩展了: 我们不仅需要对普通文件进行读写, 还需要支持各种"特殊文件"的操作. 至于扩展的方式, 你是再熟悉不过的了, 那就是抽象!

我们对之前实现的文件操作API的语义进行扩展, 让它们可以支持任意文件(包括"特殊文件")的操作:

    int fs_open(const char *pathname, int flags, int mode);
    size_t fs_read(int fd, void *buf, size_t len);
    size_t fs_write(int fd, const void *buf, size_t len);
    size_t fs_lseek(int fd, size_t offset, int whence);
    int fs_close(int fd);
    

这组扩展语义之后的API有一个酷炫的名字, 叫[VFS(虚拟文件系统)open in new window](https://en.wikipedia.org/wiki/Virtual_file_system). 既然有虚拟文件系统, 那相应地也应该有"真实文件系统", 这里所谓的真实文件系统, 其实是指具体如何操作某一类文件. 比如在Nanos-lite上, 普通文件通过ramdisk的API进行操作; 在真实的操作系统上, 真实文件系统的种类更是数不胜数: 比如熟悉Windows的你应该知道管理普通文件的NTFS, 目前在GNU/Linux上比较流行的则是EXT4; 至于特殊文件的种类就更多了, 于是相应地有`procfs`, `tmpfs`, `devfs`, `sysfs`, `initramfs`... 这些不同的真实文件系统, 它们都分别实现了这些文件的具体操作方式.

所以, VFS其实是对不同种类的真实文件系统的抽象, 它用一组API来描述了这些真实文件系统的抽象行为, 屏蔽了真实文件系统之间的差异, 上层模块(比如系统调用处理函数)不必关心当前操作的文件具体是什么类型, 只要调用这一组API即可完成相应的文件操作. 有了VFS的概念, 要添加一个真实文件系统就非常容易了: 只要把真实文件系统的访问方式包装成VFS的API, 上层模块无需修改任何代码, 就能支持一个新的真实文件系统了.

#### 又来了

阅读上述文字的时候, 如果你想起了AM的概念, 这就对了, 因为VFS背后的思想, 也是抽象.

在Nanos-lite中, 实现VFS的关键就是`Finfo`结构体中的两个读写函数指针:

    typedef struct {
      char *name;         // 文件名
      size_t size;        // 文件大小
      size_t disk_offset;  // 文件在ramdisk中的偏移
      ReadFn read;        // 读函数指针
      WriteFn write;      // 写函数指针
    } Finfo;
    

其中`ReadFn`和`WriteFn`分别是两种函数指针, 它们用于指向真正进行读写的函数, 并返回成功读写的字节数. 有了这两个函数指针, 我们只需要在文件记录表中对不同的文件设置不同的读写函数, 就可以通过`f->read()`和`f->write()`的方式来调用具体的读写函数了.

#### 用C语言模拟面向对象编程

VFS的实现展示了如何用C语言来模拟面向对象编程的一些基本概念: 例如通过结构体来实现类的定义, 结构体中的普通变量可以看作类的成员, 函数指针就可以看作类的方法, 给函数指针设置不同的函数可以实现方法的重载...

这说明, OOP中那些看似虚无缥缈的概念也没比C语言高级到哪里去, 只不过是OOP的编译器帮我们做了更多的事情, 编译成机器代码之后, OOP也就不存在了. [Object-Oriented Programming With ANSI-Copen in new window](https://www.cs.rit.edu/~ats/books/ooc.pdf) 这本书专门介绍了如何用ANSI-C来模拟OOP的各种概念和功能. 在GNU/Linux的内核代码中, 很多地方也有OOP的影子.

不过在Nanos-lite中, 由于特殊文件的数量很少, 我们约定, 当上述的函数指针为`NULL`时, 表示相应文件是一个普通文件, 通过ramdisk的API来进行文件的读写, 这样我们就不需要为大多数的普通文件显式指定ramdisk的读写函数了.

我们把文件看成字节序列, 大部分字节序列都是"静止"的, 例如对于ramdisk和磁盘上的文件, 如果我们不对它们进行修改, 它们就会一直位于同一个地方, 这样的字节序列具有"位置"的概念; 但有一些特殊的字节序列并不是这样, 例如键入按键的字节序列是"流动"的, 被读出之后就不存在了, 这样的字节序列中的字节之间只有顺序关系, 但无法编号, 因此它们没有"位置"的概念. 属于前者的文件支持`lseek`操作, 存储这些文件的设备称为"块设备"; 而属于后者的文件则不支持`lseek`操作, 相应的设备称为"字符设备". 真实的操作系统还会对`lseek`操作进行抽象, 我们在Nanos-lite中进行了简化, 就不实现这一抽象了.

### [#](#操作系统之上的ioe) 操作系统之上的IOE

有了VFS, 要把IOE抽象成文件就非常简单了.

首先当然是来看最简单的输出设备: 串口. 在Nanos-lite中, `stdout`和`stderr`都会输出到串口. 之前你可能会通过判断`fd`是否为`1`或`2`, 来决定`sys_write()`是否写入到串口. 现在有了VFS, 我们就不需要让系统调用处理函数关心这些特殊文件的情况了: 我们只需要在`nanos-lite/src/device.c`中实现`serial_write()`, 然后在文件记录表中设置相应的写函数, 就可以实现上述功能了. 由于串口是一个字符设备, 对应的字节序列没有"位置"的概念, 因此`serial_write()`中的`offset`参数可以忽略. 另外Nanos-lite也不打算支持`stdin`的读入, 因此在文件记录表中设置相应的报错函数即可.

#### 把串口抽象成文件

根据上述内容, 让VFS支持串口的写入.

关于输入设备, 我们先来看看时钟. 时钟比较特殊, 大部分操作系统并没有把它抽象成一个文件, 而是直接提供一些和时钟相关的系统调用来给用户程序访问. 在Nanos-lite中, 我们也提供一个`SYS_gettimeofday`系统调用, 用户程序可以通过它读出当前的系统时间.

#### 实现gettimeofday

实现`gettimeofday`系统调用, 这一系统调用的参数含义请RTFM. 实现后, 在`navy-apps/tests/`中新增一个`timer-test`测试, 在测试中通过`gettimeofday()`获取当前时间, 并每过0.5秒输出一句话.

为了更好地封装IOE的功能, 我们在Navy中提供了一个叫NDL(NJU DirectMedia Layer)的多媒体库. 这个库的代码位于`navy-apps/libs/libndl/NDL.c`中, 但大部分的功能都没有实现. 代码中有一些和`NWM_APP`相关的内容, 你目前可以忽略它们, 但不要修改相关代码, 你将会在PA4的最后体验相关的功能. NDL向用户提供了一个和时钟相关的API:

    // 以毫秒为单位返回系统时间
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