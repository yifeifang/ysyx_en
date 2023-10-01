[#](#Batch Processing System) Batch Processing System
=================

#### There are no bugs that cannot be fixed, only systems that we do not understand

PA3 is a watershed for the entire PA. Starting from PA3, the complexity of the system begins to gradually increase, more and more abstraction layers will be added, the system will begin to gradually improve, and the applications will become more realistic.

This means that the bug propagation chain will become more complex, and debugging will increasingly test your understanding of system behavior. If you used to get help from others and did not understand the details of the system during the debugging process, you will find that the gap between you and others is rapidly widening in PA3: others are becoming more and more proficient in mastering the entire system, while you find it more and more difficult to move forward as you go forward. For example, the handouts and codes become increasingly difficult to understand, and the bugs become more and more difficult to understand. Getting more and more mysterious.

There is only one way to remedy the situation: you really can’t be lazy anymore.

We have implemented a von Neumann computer system in PA2, and have run typing games and FCEUX on AM. With IOE, almost all kinds of small games can be transplanted to AM to run. These small games running mode on the computer have one characteristic that they will monopolize the entire computer system: we can always play typing games on NEMU. When we don't want to play, we will exit NEMU and re-run FCEUX to play.

In fact, this is how early computers worked: the system administrator loaded a specific program (actually a punch card from ancient times) into the computer, and the computer would continue to execute the program until the program ended or the administrator manually terminated it. Then the administrator manually loads the next program. The programs back then were far from as cool as the Super Mario you played, and most of them were scientific calculations and physical modeling tasks (such as ballistic trajectory calculations).

Later, people thought that it would be too troublesome for the administrator to manually load new programs every time. Recalling the way the von Neumann computer works, one of its characteristics is: when the computer completes executing an instruction, Then automatically execute the next instruction. Similarly, can we let the administrator prepare a set of programs in advance, and let the computer automatically execute the next program after executing one program?

That is the concept of [Batch Processing System](https://en.wikipedia.org/wiki/Batch_processing), With the batch processing system, the administrator's hands can be freed. The key to the batch processing system is to have a background program. When a foreground program ends, the background program will automatically load a new foreground program to execute.

Such a background program is actually an operating system. Yes, you heard it right, this background program that sounds like it does nothing is really an operating system! Speaking of operating systems, you may immediately think of Windows with several GB of installation packages. But in fact, the earliest operating system [GM-NAA I](https://en.wikipedia.org/wiki/GM-NAA_I/O) put into use in history was born in 1956, and one of its main tasks is to Go to "Automatically load new programs".

#### What is an operating system? (It is recommended to think about it in the second trail)

This is a big deal, and we encourage you to come back and revisit it after taking the operating system course.

### [#](#The simplest operating system) The simplest operating system

Seeing is believing, let’s first show how simple the operating system can be. The operating system used in PA is called Nanos-lite, which is a tailored version of Nanjing University’s operating system Nanos. It is an operating system tailor-made for PA . By writing Nanos-lite code, you will realize how the operating system uses the mechanisms provided by the hardware (that is, ISA and AM) to support the running of the program, which is also in line with the ultimate goal of PA. As for the full version of Nanos , you will see its true colors in the operating system course next semester.

We have prepared the framework code of Nanos-lite for everyone, which can be obtained by executing the following command:

    cd ics2023
    bash init.sh nanos-lite
    

Nanos-lite contains all modules used in subsequent PAs, but the specific functions of most modules have not been implemented. Since the functions of the hardware (NEMU) are gradually added, Nanos-lite must also cooperate with this process. You will use some macros in `nanos-lite/include/common.h` which are used to control the functions of Nanos-lite during the experiment. As the experimental progress progresses, we will gradually explain all the modules, and Nanos-lite will do more and more work. Therefore, when reading the code of Nanos-lite, you only need to care about the modules related to the current progress, and do not get entangled in the code that is not related to the current progress.

    nanos-lite
    ├── include
    │   ├── common.h
    │   ├── debug.h
    │   ├── fs.h
    │   ├── memory.h
    │   └── proc.h
    ├── Makefile
    ├── README.md
    ├── resources
    │   └── logo.txt    # Project-N logo文本
    └── src
        ├── device.c    # Device abstraction
        ├── fs.c        # File System
        ├── irq.c       # Interrupt exception handling
        ├── loader.c    # Loader
        ├── main.c
        ├── mm.c        # Storage management
        ├── proc.c      # Process scheduling
        ├── ramdisk.c   # ramdisk driver
        ├── resources.S # ramdisk content and logo of Project-N
        └── syscall.c   # System call handling
    

It should be reminded that Nanos-lite runs on AM, and AM’s APIs are available in Nanos-lite. Although the operating system is a special concept to us, from AM's perspective, it is just an ordinary C program that calls the AM API, no different from Super Mario. At the same time, you will once again realize the benefits of AM: the implementation of Nanos-lite can be architecture-independent, which means that no matter which ISA you have chosen before, you can easily run Nanos-lite, and even you can Just like developing klib, debug your Nanos-lite on `native`.

In addition, although it will not cause obvious misunderstandings, after the introduction of Nanos-lite, we will still use the concept of "user process" instead of "user program" in some places. If you can't understand what a process is now, you only need to understand the process as a "running program". Still can’t feel the difference between the two? Let’s give a simple example. If you open Notepad three times, there will be three Notepad processes running on the computer, but there is only one Notepad program on the disk. Process is an important concept in the operating system. Detailed knowledge about processes will be introduced in the operating system class.

At the beginning, all macros related to the experimental progress in `nanos-lite/include/common.h` are not defined. At this time, the function of Nanos-lite is very simple. Let's briefly sort out the current behavior of Nanos-lite:

1.  Print the logo of Project-N, and output hello information and compilation time through `Log()`. It should be noted that the `Log()` macro defined in Nanos-lite is not the `Log()` macro defined in NEMU . Nanos-lite and NEMU are two independent projects, and their codes will not affect each other. You need to pay attention to this when reading the code. In Nanos-lite, the `Log()` macro outputs through the `printf()` you wrote in `klib`, which will eventually call TRM's `patch()`.
2.  Call `init_device()` to perform some initialization operations on the device. Currently `init_device()` will directly call `ioe_init()`.
3.  Initialize the ramdisk. Generally speaking, the program should be stored in a permanent storage medium (such as a disk). However, simulating a disk in NEMU is a slightly complicated task, so first let Nanos-lite use a section of memory as a disk. Such a disk has a special name, called ramdisk.
4.  `init_fs()` and `init_proc()` are used to initialize the file system and create processes respectively. Currently, they do not perform meaningful operations, so you can ignore them.
5.  Call `panic()` to end the running of Nanos-lite.

Since Nanos-lite is essentially an AM program, we can compile/run Nanos-lite in the same way. Execute 

    make ARCH=$ISA-nemu run
    

in the `nanos-lite/` directory. In addition, as mentioned above, you can also compile Nanos-lite to `native` and run it to help you debug.

#### The operating system is a C program

You may not believe it, but the .c and .h files of the framework code undoubtedly contain this ironclad fact, and there is nothing special about even the compilation method. The same is true for GNU/Linux: If you read it If you look at the source code, you will find that GNU/Linux is just a huge C program.

So compared with ordinary C programs, what is special about the operating system? After completing PA3, I believe you will know something about it.

The operating system provided by the framework code really does nothing! Looking back at history, to implement the simplest operating system, it is necessary to implement the following two functions:

*   After the user program is executed, it can jump to the operating system code to continue execution.
*   The operating system can load a new user program to execute

### [#](#来自操作系统的新需求) 来自操作系统的新需求

仔细思考, 我们就会发现, 上述两点功能中其实蕴含着一个新的需求: 程序之间的执行流切换. 我们知道函数调用一般是在一个程序内部发生的(动态链接库除外), 属于程序内部的执行流切换, 使用call/jal指令即可实现. 而上述两点需求需要在操作系统和用户程序之间进行执行流的切换. 不过, 执行流切换的本质, 也只是把PC从一个值修改成另一个值而已(黑客眼中就是这么理解的). 那么, 我们能否也使用call/jal指令来实现程序之间的执行流切换呢?

也许在GM-NAA I/O诞生的那个年代, 大家说不定还真是这样做的: 操作系统就是一个库函数, 用户程序退出的时候, 调用一下这个特殊的库函数就可以了, 就像我们在AM的程序中调用`halt()`一样. 不过, 后来人们逐渐认识到, 操作系统和其它用户程序还是不太一样的: 一个用户程序出错了, 操作系统可以运行下一个用户程序; 但如果操作系统崩溃了, 整个计算机系统都将无法工作. 所以, 人们还是希望能把操作系统保护起来, 尽量保证它可以正确工作.

在这个需求面前, 用call/jal指令来进行操作系统和用户进程之间的切换就显得太随意了. 操作系统的本质也是一个程序, 也是由函数构成的, 但无论用户程序是无意还是有心, 我们都不希望它可以把执行流切换到操作系统中的任意函数. 我们所希望的, 是一种可以限制入口的执行流切换方式, 显然, 这种方式是无法通过程序代码来实现的.

### [#](#等级森严的制度) 等级森严的制度

为了阻止程序将执行流切换到操作系统的任意位置, 硬件中逐渐出现保护机制相关的功能, 比如i386中引入了保护模式(protected mode)和特权级(privilege level)的概念, 而mips32处理器可以运行在内核模式和用户模式, riscv32则有机器模式(M-mode), 监控者模式(S-mode)和用户模式(U-mode). 这些概念的思想都是类似的: 简单地说, 只有高特权级的程序才能去执行一些系统级别的操作, 如果一个特权级低的程序尝试执行它没有权限执行的操作, CPU将会抛出一个异常信号, 来阻止这一非法行为的发生. 一般来说, 最适合担任系统管理员的角色就是操作系统了, 它拥有最高的特权级, 可以执行所有操作; 而除非经过允许, 运行在操作系统上的用户程序一般都处于最低的特权级, 如果它试图破坏社会的和谐, 它将会被判"死刑".

以支持现代操作系统的RISC-V处理器为例, 它们存在M, S, U三个特权模式, 分别代表机器模式, 监管者模式和用户模式. M模式特权级最高, U模式特权级最低, 低特权级能访问的资源, 高特权级也能访问. 那CPU是怎么判断一个进程是否执行了无权限操作呢? 答案很简单, 只要在硬件上维护一个用于标识当前特权模式的寄存器(属于计算机状态的一部分), 然后在访问那些高特权级才能访问的资源时, 对当前特权模式进行检查. 例如RISC-V中有一条特权指令`sfence.vma`, 手册要求只有当处理器当前的特权模式不低于S模式才能执行, 因此我们可以在硬件上添加一些简单的逻辑来实现特权模式的检查:

    is_sfence_vma_ok = (priv_mode == M_MODE) || (priv_mode == S_MODE);
    

可以看到, 特权模式的检查只不过是一些门电路而已. 如果检查不通过, 此次操作将会被判定为非法操作, CPU将会抛出异常信号, 并跳转到一个和操作系统约定好的内存位置, 交由操作系统进行后续处理.

通常来说, 操作系统运行在S模式, 因此有权限访问所有的代码和数据; 而一般的程序运行在U模式, 这就决定了它只能访问U模式的代码和数据. 这样, 只要操作系统将其私有代码和数据放S模式中, 恶意程序就永远没有办法访问到它们.

类似地, x86的操作系统运行在ring 0, 用户进程运行在ring 3; mips32的操作系统运行在内核模式, 用户进程运行在用户模式. 这些保护相关的概念和检查过程都是通过硬件实现的, 只要软件运行在硬件上面, 都无法逃出这一天网. 硬件保护机制使得恶意程序永远无法全身而退, 为构建计算机和谐社会作出了巨大的贡献.

这是多美妙的功能! 遗憾的是, 上面提到的很多概念其实只是一带而过, 真正的保护机制也还需要考虑更多的细节. ISA手册中一般都会专门有一章来描述保护机制, 这就已经看出来保护机制并不是简单说说而已. 根据KISS法则, 我们并不打算在NEMU中加入保护机制. 我们让所有用户进程都运行在最高特权级, 虽然所有用户进程都有权限执行所有指令, 不过由于PA中的用户程序都是我们自己编写的, 一切还是在我们的控制范围之内. 毕竟, 我们也已经从上面的故事中体会到保护机制的本质了: 在硬件中加入一些与特权级检查相关的门电路(例如比较器电路), 如果发现了非法操作, 就会抛出一个异常信号, 让CPU跳转到一个约定好的目标位置, 并进行后续处理.

#### 分崩离析的秩序

特权级保护是现代计算机系统的一个核心机制, 但并不是有了这一等级森严的制度就高枕无忧了, 黑客们总是会绞尽脑汁去试探这一制度的边界. 最近席卷计算机领域的, 就要数2018年1月爆出的[Meltdown和Spectreopen in new window](https://meltdownattack.com/)这两个大名鼎鼎的硬件漏洞了. 这两个史诗级别的漏洞之所以震惊全世界, 是因为它们打破了特权级的边界: 恶意程序在特定的条件下可以以极高的速率窃取操作系统的信息. Intel的芯片被指出均存在Meltdown漏洞, 而Spectre漏洞则是危害着所有架构的芯片, 无一幸免, 可谓目前为止体系结构历史上影响最大的两个漏洞了. 如果你执行`cat /proc/cpuinfo`, 你可能会在`bugs`信息中看到这两个漏洞的影子.

Meltdown和Spectre给过去那些一味追求性能的芯片设计师敲响了警钟: 没有安全, 芯片跑得再快, 也是徒然. 有趣的是, 直接为这场闹剧买单的, 竟然是各大云计算平台的工程师们: 漏洞被爆出的那一周时间, 阿里云和微软Azure的工程师连续通宵加班, 想尽办法给云平台打上安全补丁, 以避免客户的数据被恶意窃取.

不过作为教学实验, 安全这个话题离PA还是太遥远了, 甚至性能也不是PA的主要目标. 这个例子想说的是, 真实的计算机系统非常复杂, 远远没到完美的程度. 这些漏洞的出现从某种程度上也说明了, 人们已经没法一下子完全想明白每个模块之间的相互影响了; 但计算机背后的原理都是一脉相承的, 在一个小而精的教学系统中理解这些原理, 然后去理解, 去改进真实的系统, 这也是做PA的一种宝贵的收获.