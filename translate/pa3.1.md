[#](#Batch-Processing-System) Batch Processing System
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

### [#](#The-simplest-operating-system) The simplest operating system

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

### [#](#New-requirements-from-the-operating-system) New requirements from the operating system

If we think about it carefully, we will find that the above two functions actually contain a new requirement: execution flow switching between programs. We know that function calls generally occur within a program (except for dynamic link libraries), and are execution flow switching within the program, which can be achieved using the call/jal instruction. The above two requirements require execution flow switching between the operating system and the user program. However, the essence of execution flow switching is just to modify the PC from one value to another value (this is how hackers understand it). So, can we also use the call/jal instruction to switch the execution flow between programs?

Maybe in the era when GM-NAA I/O was born, everyone might actually do this: the operating system is a library function, and when the user program exits, just call this special library function, just like we call `halt()` in AM programs. However, later people gradually realized that the operating system is still different from other user programs: if one user program fails, the operating system can run the next user program; but if the operating system crashes, the entire computer system will not work. Therefore, people still hope to protect the operating system and try to ensure that it can work correctly.

In the face of this demand, it seems too arbitrary to use the call/jal instruction to switch between the operating system and the user process. The essence of the operating system is also a program, and it is also composed of functions. However, no matter whether the user program is unintentional or intentional, we do not want it to be able to switch the execution flow to any function in the operating system. What we hope for is an execution flow switching method that can limit the entry point. Obviously, this method cannot be implemented through program code.

### [#](#strict-hierarchical-system) strict hierarchical system

In order to prevent the program from switching the execution flow to any location in the operating system, functions related to protection mechanisms gradually appear in the hardware. For example, i386 introduced the concepts of protected mode and privilege level, while the mips32 processor can run in kernel mode and user mode, riscv32 has machine mode (M-mode), supervisor mode (S-mode) and user mode (U-mode). The ideas of these concepts are similar: simply put, only high-privileged programs can perform some system-level operations. If a low-privileged program tries to perform operations that it does not have permission to perform, the CPU will throw a exception signal to prevent this illegal behavior from happening. Generally speaking, the most suitable role for a system administrator is the operating system, which has the highest privilege level and can perform all operations; unless permitted, user programs running on the operating system are generally at the lowest privilege level, if it attempts to destroy social harmony, it will be sentenced to "death".

Taking RISC-V processors that support modern operating systems as an example, they have three privileged modes: M, S, and U, which represent machine mode, supervisor mode and user mode respectively. M mode has the highest privilege level, and U mode has the lowest privilege level. Resources that can be accessed by low privilege levels can also be accessed by high privilege levels. So how does the CPU determine whether a process has performed an unauthorized operation? The answer is simple, just maintain a register on the hardware that identifies the current privilege mode (part of the computer state), and then check the current privilege mode when accessing resources that can only be accessed by high privilege levels. For example, there is a privileged instruction `sfence.vma` in RISC-V. The manual requires that it can only be executed when the current privilege mode of the processor is not lower than S mode. Therefore, we can add some simple logic to the hardware to implement the privilege mode check:

    is_sfence_vma_ok = (priv_mode == M_MODE) || (priv_mode == S_MODE);
    

As you can see, the checks in privileged mode are just some gate circuits. If the check fails, the operation will be judged as an illegal operation, and the CPU will throw an exception signal and jump to a memory location agreed with the operating system, which will be handed over to the operating system for subsequent processing.

Generally speaking, the operating system runs in S mode, so it has permission to access all codes and data; while a general program runs in U mode, which determines that it can only access U mode code and data. In this way, as long as the operating system puts its private code and data in S mode, malicious programs will never be able to access them.

Similarly, the x86 operating system runs in ring 0 and user processes run in ring 3; the mips32 operating system runs in kernel mode and user processes run in user mode. These protection-related concepts and inspection processes are all implemented through hardware. As long as the software runs on the hardware, it cannot escape this skynet. The hardware protection mechanism prevents malicious programs from ever escaping, making a huge contribution to building a harmonious computer society.

What a wonderful feature! Unfortunately, many of the concepts mentioned above are only superficial, and the real protection mechanism also needs to consider more details. ISA manuals usually have a dedicated chapter to describe the protection mechanism, which already shows that the protection mechanism is not just a simple talk. According to the KISS (Keep It Simple, Stupid) rule, we do not plan to add a protection mechanism to NEMU. We let all user processes run at the highest privilege level. Although all user processes have the permission to execute all instructions, since the user programs in PA are all written by ourselves, everything is still within our control. After all, we have already experienced the essence of the protection mechanism from the above story: add some gate circuits related to privilege level checking (such as comparator circuits) to the hardware. If an illegal operation is found, an exception signal will be thrown, allowing the CPU to jump to an agreed target location and perform subsequent processing.

#### 分崩离析的秩序

特权级保护是现代计算机系统的一个核心机制, 但并不是有了这一等级森严的制度就高枕无忧了, 黑客们总是会绞尽脑汁去试探这一制度的边界. 最近席卷计算机领域的, 就要数2018年1月爆出的[Meltdown和Spectreopen in new window](https://meltdownattack.com/)这两个大名鼎鼎的硬件漏洞了. 这两个史诗级别的漏洞之所以震惊全世界, 是因为它们打破了特权级的边界: 恶意程序在特定的条件下可以以极高的速率窃取操作系统的信息. Intel的芯片被指出均存在Meltdown漏洞, 而Spectre漏洞则是危害着所有架构的芯片, 无一幸免, 可谓目前为止体系结构历史上影响最大的两个漏洞了. 如果你执行`cat /proc/cpuinfo`, 你可能会在`bugs`信息中看到这两个漏洞的影子.

Meltdown和Spectre给过去那些一味追求性能的芯片设计师敲响了警钟: 没有安全, 芯片跑得再快, 也是徒然. 有趣的是, 直接为这场闹剧买单的, 竟然是各大云计算平台的工程师们: 漏洞被爆出的那一周时间, 阿里云和微软Azure的工程师连续通宵加班, 想尽办法给云平台打上安全补丁, 以避免客户的数据被恶意窃取.

不过作为教学实验, 安全这个话题离PA还是太遥远了, 甚至性能也不是PA的主要目标. 这个例子想说的是, 真实的计算机系统非常复杂, 远远没到完美的程度. 这些漏洞的出现从某种程度上也说明了, 人们已经没法一下子完全想明白每个模块之间的相互影响了; 但计算机背后的原理都是一脉相承的, 在一个小而精的教学系统中理解这些原理, 然后去理解, 去改进真实的系统, 这也是做PA的一种宝贵的收获.