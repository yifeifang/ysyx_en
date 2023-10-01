[#](#User-programs-and-system-calls) User programs and system calls
=========================

With the trap instruction, the user program can switch the execution flow to the entry specified by the operating system. Now we have to solve the second problem of implementing the batch processing system: how to load the user program.

### [#](#Load-the-first-user-program) Load the first user program

In the operating system, the loader module is responsible for loading user programs. We know that programs include code and data, which are stored in executable files. The loading process is to place the code and data in the executable file in the correct memory location, and then jump to the program entry, and the program will start executing. More specifically, in order to implement the `loader()` function, we need to solve the following problems:

*   Where is the executable file?
*   Where are the code and data located in the executable file?
*   How much code and data is there?
*   Where is the "correct memory location"?

In order to answer the first question, we need to first explain where the user program comes from. User programs run on the operating system. Due to differences in runtime environments, we cannot run programs compiled on AM on the operating system. Therefore, we have prepared a new sub-project Navy-apps, specifically used to compile user programs for the operating system. Obtain Navy's framework code by executing the following command:

    cd ics2023
    bash init.sh navy-apps
    

The structure of the Navy sub-project is organized as follows, more instructions can be read in `README.md`:

    navy-apps
    ├── apps            # User program
    │   ├── am-kernels
    │   ├── busybox
    │   ├── fceux
    │   ├── lua
    │   ├── menu
    │   ├── nplayer
    │   ├── nslider
    │   ├── nterm
    │   ├── nwm
    │   ├── onscripter
    │   ├── oslab0
    │   └── pal         # Xian Jian Qi Xia Zhuan (also called Chinese PAL)
    ├── fsimg           # Root file system
    ├── libs            # Runtime library
    │   ├── libc        # Newlib C library
    │   ├── libam
    │   ├── libbdf
    │   ├── libbmp
    │   ├── libfixedptc
    │   ├── libminiSDL
    │   ├── libndl
    │   ├── libos       # User-level encapsulation of system calls
    │   ├── libSDL_image
    │   ├── libSDL_mixer
    │   ├── libSDL_ttf
    │   └── libvorbis
    ├── Makefile
    ├── README.md
    ├── scripts
    └── tests           # Some tests
    

Navy's `Makefile` organization is very similar to `abstract-machine`, you should easily understand it. Among them, `navy-apps/libs/libc` is a project named [Newlib](https://sourceware.org/newlib/), which is a C library specially provided for embedded systems. The function in newlib has extremely low requirements on the runtime environment. This is very friendly to Nanos-lite. We do not have to implement additional functions in Nanos-lite to cooperate with the C library. The entry point of the user program is located in the `_start()` function in `navy-apps/libs/libos/src/crt0/start.S`. `crt` here is the abbreviation of `C RunTime`, and `0` means the beginning. The `_start()` function will call the `call_main()` function in `navy-apps/libs/libos/src/crt0/crt0.c`, and then call the `main()` function of the user program, after returning from the `main()` function, `exit()` will be called to end the operation.

#### C library code is "always" correct

A student once thought that there was a bug in the C library code when he was debugging, and after modifying the C library code, it worked successfully. In fact, the mandatory contents of PA do not need to modify the C library code. Modifying the C library code to make the program run successfully means that the bug is still in your code. By modifying the C library you are bypassing a bug that you have already found, it is not resolved, it goes back to a latent state, you will probably encounter it again in the future, the code required to resolve it may be larger, and when you do encounter it it will be difficult to determine if it is the same bug or not.

In short, when you decide to speculate, you need to calmly analyze the pros and cons before making a decision.

The first user program we want to run on Nanos-lite is `navy-apps/tests/dummy/dummy.c`. In order to avoid conflicts with the contents of Nanos-lite, we have agreed that the current user program needs to be linked near memory location `0x3000000` (x86) or `0x83000000` (mips32 or riscv32), and Navy has set the appropriate options (see `LDFLAGS` variable in `navy-apps/scripts/$ISA.mk`). In order to compile dummy, run 

    make ISA=$ISA
    
in the `navy-apps/tests/dummy/` directory

The first time you compile in Navy, you will get Newlib and other projects from github and compile them, there will be a lot of warnings during the compilation process, so you can ignore them for now. After compilation, copy `navy-apps/tests/dummy/build/dummy-$ISA` and rename it to `nanos-lite/build/ramdisk.img`, and then execute the following in the `nanos-lite/` directory

    make ARCH=$ISA-nemu
    

The Nanos-lite executable is generated, and the ramdisk image `nanos-lite/build/ramdisk.img` is included as part of Nanos-lite during compilation (implemented in `nanos-lite/src/resources.S`). The ramdisk is now very simple, it has only one file, the user program `dummy`, which will be loaded, which in fact answers the first question above: the executable is located at offset 0 of the ramdisk, and accessing it will give you the first byte of the user program.

To answer the rest of the questions, we first need to understand how executables are organized. You've already studied the ELF file format in class, which contains not only the code and static data of the program itself, but also some information that describes it, otherwise we wouldn't even know where the boundary between code and data is. This information describes the organization of the executable file, different organization forms different executable file formats, for example, the mainstream Windows executable file is [PE (Portable Executable)](https://en.wikipedia.org/wiki/Portable_Executable) format, while GNU/Linux mainly use [ELF (Executable and Linkable Format)](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format) format. Therefore, in general, you cannot copy an executable file from Windows to GNU/Linux and vice versa. ELF is the standard format for GNU/Linux executables because GNU/Linux follows the System V ABI ([Application Binary Interface](http://stackoverflow.com/questions/2171177/what-is-application-binary-interface-abi)).

#### Where's the heap and stack?

We mentioned that the code and data are in the executable, but we didn't mention the heap and stack. Why aren't the contents of the heap and stack in the executable? And where do the heap and stack come from when the program is running? Does AM's code give you any ideas?

#### How to recognize executables in different formats?

If you execute an executable file under GNU/Linux that was copied from Windows, it will report a "format error". Think about it, how does GNU/Linux know about "formatting errors"?

ELF files provide two perspectives for organizing an executable, a section perspective for the linking process, which provides information for linking and relocating (e.g., symbol tables), and an execution-oriented segment perspective, which provides information for loading the executable. With the `readelf` command, we can also see the mapping between sections and segments: a segment may consist of zero or more sections, but a section may not be included in any segment.

We are now interested in how to load the program, so we focus on the segment perspective. ELF uses a program header table to manage segments. A table entry in the program header table describes all the attributes of a segment, including its type, virtual address, flags, alignment, as well as its in-file offset and segment size. Based on this information, we know which bytes of the executable need to be loaded, and we can also see that loading an executable is not about loading all the content it contains, but only those that are relevant to the moment of operation, such as debugging information and symbol tables do not need to be loaded. We can tell if a segment needs to be loaded by determining if its `Type` attribute is `PT_LOAD`.

#### Redundant attributes?

Using `readelf` to view information about an ELF file, you will see that a segment contains two size attributes, `FileSiz` and `MemSiz`, why is that? If you look more closely, you will see that `FileSiz` is usually not larger than the corresponding `MemSiz`, why is that?

We illustrate how to load a segment based on its attributes with the following diagram:

          +-------+---------------+-----------------------+
          |       |...............|                       |
          |       |...............|                       |  ELF file
          |       |...............|                       |
          +-------+---------------+-----------------------+
          0       ^               |              
                  |<------+------>|       
                  |       |       |             
                  |       |                            
                  |       +----------------------------+       
                  |                                    |       
       Type       |   Offset    VirtAddr    PhysAddr   |FileSiz  MemSiz   Flg  Align
       LOAD       +-- 0x001000  0x03000000  0x03000000 +0x1d600  0x27240  RWE  0x1000
                                   |                       |       |     
                                   |   +-------------------+       |     
                                   |   |                           |     
                                   |   |     |           |         |       
                                   |   |     |           |         |      
                                   |   |     +-----------+ ---     |     
                                   |   |     |00000000000|  ^      |   
                                   |   | --- |00000000000|  |      |    
                                   |   |  ^  |...........|  |      |  
                                   |   |  |  |...........|  +------+
                                   |   +--+  |...........|  |      
                                   |      |  |...........|  |     
                                   |      v  |...........|  v    
                                   +-------> +-----------+ ---  
                                             |           |     
                                             |           |    
                                                Memory  
    

You need to find out the `Offset`, `VirtAddr`, `FileSiz` and `MemSiz` parameters for each segment to be loaded. The relative file offset `Offset` indicates that the content of the corresponding segment starts at the `Offset` byte of the ELF file, and its size in the file is `FileSiz`, and it needs to be allocated to a virtual memory location with the `VirtAddr` header address, and its size in memory is `MemSiz`. In other words, the memory used by the segment is the contiguous interval `[VirtAddr, VirtAddr + MemSiz)`, and then the content of the segment is read from the ELF file into this memory interval and the physical interval `[VirtAddr + FileSiz, VirtAddr + MemSiz)` is zeroed out.

#### Why do you need to clear it?

Why do I need to zero out the physical interval corresponding to `[VirtAddr + FileSiz, VirtAddr + MemSiz)`?

For more information on where programs come from, see the article [COMPILER, ASSEMBLER, LINKER AND LOADER: A BRIEF STORY](http://www.tenouk.com/ModuleW.html). If you would like to see more information about ELF files, see the manual

    man 5 elf
    

Since the ELF files are in ramdisk, the framework code provides some ramdisk-related functions (defined in `nanos-lite/src/ramdisk.c`), which you can use to implement the loader.

    // Read `len` bytes from `offset` offset in ramdisk into `buf`
    size_t ramdisk_read(void *buf, size_t offset, size_t len);
    
    // Write `len` bytes from `buf` to `offset` offset in ramdisk
    size_t ramdisk_write(const void *buf, size_t offset, size_t len);
    
    // Returns the size of the ramdisk in bytes
    size_t get_ramdisk_size();
    

In fact, the work of the loader shows us the program in its most primitive state: the bit string! The loader is actually a program that puts this unobtrusive string of bits in the right place, but it reflects the epochal idea of the "stored program": when the operating system gives it control, the computer interprets it as an instruction and executes it line by line. The loader pushes the life cycle of the computer beyond the boundaries of the program: the end of a program does not mean that the computer stops working, but that the computer will carry out its mission of executing the program for the rest of its life.

#### Implementing the loader

You need to implement the loader function in Nanos-lite to load the user program into the correct memory location and then execute the user program. The `loader()` function is defined in `nanos-lite/src/loader.c`, where the `pcb` parameter can be ignored as it is not used at the moment, and the `filename` parameter can be ignored as there is only one file in the ramdisk. The `filename` parameter can be ignored because there is only one file in the ramdisk. The `filename` parameter will come in handy in the next phase of the filesystem implementation.

Once implemented, call `naive_uload(NULL, NULL)` in `init_proc()`, which will call your implemented loader to load the first user program, and then jump to the user program for execution. If your implementation is correct, you will see an unhandled event #4 triggered in Nanos-lite when the `dummy` program is executed. This means that the loader has successfully loaded dummy, and has successfully jumped into dummy for execution. The unhandled event is described later.

#### Checking the magic number of an ELF file

We know that ELF files have a special magic number at the beginning of the file, in order to prevent the loader from loading a file that is not in ELF format, we can check the magic number in the loader:

    assert(*(uint32_t *)elf->e_ident == 0xBadC0de);
    

You need to replace the above `0xBadC0de` with the correct magic number.

Don't underestimate the apparent stupidity of `assert()`, and thank goodness when it catches you one day when your hands are shaking and you don't know what you've done.

#### Detecting the ISA type of an ELF file

There is a good chance that you will inadvertently allow `native` Nanos-lite to load and run an x86/mips32/riscv32 dummy. From an ISA specification point of view, this behavior is clearly a UB, and in particular, usually results in some incomprehensible error. To avoid this, you can detect the ISA type of the ELF file in the loader. We can filter the expected ISA type by some macros defined in AM.

    #if defined(__ISA_AM_NATIVE__)
    # define EXPECT_TYPE EM_X86_64
    #elif defined(__ISA_X86__)
    # define EXPECT_TYPE ...  // see /usr/include/elf.h to get the right type
    ...
    #else
    # error Unsupported ISA
    #endif
    

Then compare it to one of the fields in the ELF information, and if you find that the ISA type of the ELF file to be loaded does not match what is expected, report an error. If you don't know where the macros are defined in AM, RTFSC. If you don't know which field in ELF to compare against, RTFM.

#### Compiling Nanos-lite to native

You can test your Nanos-lite implementation on `native` to see if it is correct.

Since `native` is a 64-bit environment, some of ELF's data structures will be different from 32-bit, but in general, ELF's loading process is the same. To mask the differences in data structures, the macros `Elf_Ehdr` and `Elf_Phdr` are defined in `nanos-lite/src/loader.c`, and you can use them in the loader implementation.

In addition, in order to compile dummy to run on AM native's Nanos-lite, you need to compile it in Navy via `make ISA=am_native`. After that it's similar to running it on `$ISA-nemu`, i.e..

1.  Compiling dummy with `ISA=xxx`
2.  Use the compiled dummy ELF file as a ramdisk for nanos-lite
3.  Compile and run nanos-lite with `ARCH=xxx`

There is also an ISA called `native` in Navy, which is different from the ARCH mechanism called `native` in AM, and is not currently used.

### [#](#Runtime-environment-of-the-operating-system) Runtime environment of the operating system

After loading the program, let's talk about running the program. Looking back at PA2, we know that running a program requires the support of a runtime environment. The operating system wants to load and run the program, so it is naturally responsible for providing the functionality of the runtime environment. In PA2, we divided the runtime environment into two parts, depending on whether or not the implementation is related to the ISA. However, for programs running on the operating system, they do not need to interact directly with the hardware. So from what point of view should the operating system look at the runtime environment?

Notice that some of the functions of the runtime environment require the use of resources, such as physical memory for memory requests and frame buffers for screen updates. In PA2, our computer system was owned by a single program, which could play with it as much as it wanted, and it was the sole responsibility of that program to break it. In modern computer systems, there may be multiple programs using the resources of the computer system concurrently or even simultaneously. If each program uses these resources directly, and each program doesn't know what the other program is using, the whole system will soon get messed up: I'm overwriting your screen, you're overwriting my memory space...

Therefore, there needs to be a role to manage the resources in the system in a unified way: programs can not use the resources without authorization, but need to apply to the resource manager when using them. Since the operating system is at a high privileged level and enjoys supreme rights, it naturally needs to fulfill its obligations: as a resource manager managing all the resources in the system, the operating system also needs to provide services to the user programs. These services need to be presented in a uniform interface, and user programs can only request services through this interface.

This interface is the system call. This has been the mission of the operating system since its inception: we mentioned earlier that one of the main tasks of GM-NAA I/O is to load new programs, and another main function of GM-NAA I/O is to provide public interfaces for program input and output. The public interface provided by GM-NAA I/O can be considered as the original form of system calls.

#### The necessity of system calls

Are system calls necessary for batch systems? Would it be a problem to expose the AM API directly to the program in the batch system?

Thus, system calls divide the entire runtime environment into two parts, one for the operating system kernel and one for the userland. Functions that access system resources are implemented in the kernel, while the userland is reserved for functions that do not require system resources (such as `strcpy()`), as well as system call interfaces for requesting services related to system resources.

Under this model, the user program can only "compute" in the user area, and any task beyond the pure computational capability needs to be requested from the operating system through a system call. If the user program tries to perform any illegal operation, the CPU throws an exception to the operating system, causing the illegal instruction to "fail" and leaving it to the operating system to deal with. Yes, this is the hardware protection mechanism described earlier, and the operating system needs this natural barrier to prevent malicious behavior.

Just because the operating system needs to serve the user program does not mean that the operating system needs to expose all information to the user program. There is information that the user program does not need to know and should never know, such as data structures related to memory management. If a malicious program obtains this information, it may provide the basis for a malicious attack. For this reason, there is usually no system call to obtain such private data from the operating system.

### [#](#System-call) System call

So, what is the process of triggering a system call?

Real-life experience can give us some inspiration: when we go to a bank, we need to tell the staff what we want to do, what our account number is, and how much the transaction will be, just because we want the staff to know exactly what we want to do. A user program executing a system call is in a similar situation, it has to describe its needs in a way, and then tell the operating system.

Speaking of "telling the operating system", you should immediately recognize that this is done by means of a trapping instruction. In GNU/Linux, the user program triggers a system call with a trap instruction, and Nanos-lite follows this convention. CTE's `yield()` is also implemented as a trapping instruction, and although they trigger different events, the process from context saving to event distribution is very similar. Since we are triggering the system call with a trapping instruction, the most convenient way for a user program to describe its requirements to the operating system is to use the general purpose registers, because after executing the trapping instruction, the execution flow switches to the predefined entry point, and the general purpose registers are saved as part of the context. The system call handler only needs to get the necessary information from the context to know what the user program is requesting.

Navy has already prepared the system call interface for the user program. The `_syscall_()` function defined in `navy-apps/libs/libos/src/syscall.c` already implies the above process.

    intptr_t _syscall_(intptr_t type, intptr_t a0, intptr_t a1, intptr_t a2) {
      // ...
      asm volatile (SYSCALL : "=r" (ret) : "r"(_gpr1), "r"(_gpr2), "r"(_gpr3), "r"(_gpr4));
      return ret;
    }
    

The above code puts the arguments of the system call into the registers first, and then executes the trapping instruction. Since the registers and the syscall are both ISA-related, different macros are defined to abstract from them, depending on the ISA. The CTE packages this trap operation into a system call event `EVENT_SYSCALL`, which is passed on to Nanos-lite for further processing.

#### Recognition system call

Now that `dummy` has triggered the system call directly via `_syscall_()`, you need to get Nanos-lite to recognize the system call event `EVENT_SYSCALL`.

You may need to make multiple changes to the code, and when you're puzzled by the fact that the code doesn't do it right, check every detail of the process. As we have emphasized many times, it is important to understand the details.

When Nanos-lite receives a system call event, it calls the system call handler `do_syscall()`. `do_syscall()` first gets the system call parameters previously set by the user process from context `c` via macro `GPR1`, and distributes them via the first parameter - the system call number. However, Nanos-lite does not currently implement any syscalls, thus triggering panic.

Adding a syscall is easier than you think, all the information is already there. All we need to do is add the appropriate syscall number to the distribution, write the appropriate syscall handler function `sys_xxx()`, and call it. Looking back at the `dummy` program, it triggers a `SYS_yield` system call. The convention is that this system call calls the CTE's `yield()` directly, and returns `0`.

The last thing you need to do with a system call is to set the return value of the system call. For different ISAs, the return value of the system call is stored in a different register, and the macro `GPRx` is used to implement this abstraction, so we set the return value of the system call via `GPRx`.

After the CTE, the execution flow goes from `do_syscall()` all the way back to the `_syscall_()` function of the user program. The code will finally retrieve the return value of the system call from the corresponding register and return it to the caller of `_syscall_()` to inform the user program about the execution of the system call (e.g. whether it was successful or not).

#### Implementing the SYS\_yield system call

You need to:

1.  Implement the correct `GPR?` macros in the corresponding header files in the `abstract-machine/am/include/arch/` directory, so that they get the correct system call parameter registers from context `c`.
2.  Add `SYS_yield` system call.
3.  Set the return value of a system call.

Rerun the dummy program, and if you've implemented it correctly, you'll see that the dummy program has triggered another system call with the number `0`. Look at `nanos-lite/src/syscall.h`, and you will see that it is a `SYS_exit` system call. This means that the previous `SYS_yield` has returned successfully, and the `SYS_exit` is triggered because dummy has finished executing and is ready to exit.

#### Implementing the SYS\_exit system call

You need to implement the `SYS_exit` system call, which takes an exit status argument. For the sake of testing, we will call `halt()` directly with this parameter for now. After successful implementation, run the dummy program again and you will see the message `HIT GOOD TRAP`.

#### RISC-V System Call Number Passing

If you choose RISC-V, you will notice that it does not pass the syscall number through `a0`. In fact, we refer to the RISC-V Linux syscall parameter passing convention: i.e., RISC-V Linux also passes the syscall number through this register. Why do you think RISC-V Linux doesn't use `a0` to pass system call numbers?

#### Linux system calls

You can consult the Linux system calls with the following command.

*   `man syscall` - look up the syscall conventions of different architectures, including parameter passing and return values
*   `man syscalls` - look up the system calls already implemented in Linux. Oh, that's a lot, but we only need a few syscalls in PA.

### [#](#Trace-of-system-calls-strace) Trace of system calls - strace

We already know that a user program running on an operating system can only do two things, one is to perform local computation, and the other is to ask the operating system through system calls to do things that local computation cannot do. This means that if we can look at the syscall trace, we can get a better understanding of the program's behavior. There is a tool called `strace` on Linux (installable via `apt-get`) that can record the syscall trace of a user's program, and we strongly recommend you install it and try it out. For example, you can use `strace ls` to see the behavior of `ls`, and you can even see how `ls` is loaded; if you are interested in `strace` itself, you can also use `strace strace ls` to see how `strace` is implemented.

In fact, it is possible to implement a simple strace in Nanos-lite: Nanos-lite gets all the information about the system call, including the name, arguments and return value. That's why we chose to implement strace in Nanos-lite: system calls carry high-level program semantics, but NEMU can only see the underlying state machine.

#### Implementing strace

Implementing strace in Nanos-lite is a very simple task.

### [#](#TRM-for-operating-system) TRM for operating system

We have implemented two very simple system calls, so what else can a user program do on the current Nanos-lite? You may recall how we categorized the needs of programs in PA2: AM! At the most basic level, the TRM shows us what is required in order to satisfy a program's basic computational capabilities:

*   The machine provides basic arithmetic instructions
*   Can output characters
*   There are heap areas where memory can be dynamically requested
*   You can terminate the program

The basic arithmetic instructions are still provided by the machine, i.e. the instruction system you have implemented in PA2. For termination, the `SYS_exit` system call is also provided. In order to provide the user program with the ability to output characters and request memory dynamically, we need to implement more system calls.

#### [#](#Standard-output) Standard output

In GNU/Linux, output is accomplished through the `SYS_write` system call. According to the `write` function declaration (see `man 2 write`), you need to check the value of `fd` in `do_syscall()` after recognizing that the syscall number is `SYS_write`, and if `fd` is `1` or `2` (for `stdout` and `stderr`, respectively), output the `buf` first address of `len` bytes to the serial port (use `putch()` is okay). Finally, the return value must be set correctly, otherwise the caller of the system call will think that `write` was not executed successfully and retry. As for the return value of the `write` system call, see `man 2 write`. Don't forget to call the system call interface function in `_write()` in `navy-apps/libs/libos/src/syscall.c`.

In fact, the `printf()`, `cout` libraries and classes that we normally use to format strings are also called from the system call. These are examples of "system calls wrapped in library functions". The system call itself abstracts various resources of the operating system, but in order to provide a beautiful interface to the higher-level programmer, the library function will again abstract some of the system call again. For example, the library function `fwrite()`, which writes data to a file, encapsulates the `write()` system call in GNU/Linux. On the other hand, system calls depend on the specific operating system, so the encapsulation of library functions also improves program portability: in Windows, `fwrite()` encapsulates the `WriteFile()` system call, and if you use the `WriteFile()` system call directly in your code, compiling the code under GNU/Linux will result in a linking error. In a way, the abstraction of library functions does make it easier for programmers to not have to worry about the details of system calls.

By implementing the `SYS_write` system call, we have removed the biggest obstacle to using `printf()`, since after `printf()` formatting the string, will ultimately output it via the `write()` system call. The Newlib library in Navy does this for us.

#### 在Nanos-lite上运行Hello world

Navy中提供了一个`hello`测试程序(`navy-apps/tests/hello`), 它首先通过`write()`来输出一句话, 然后通过`printf()`来不断输出.

你需要实现`write()`系统调用, 然后把Nanos-lite上运行的用户程序切换成`hello`程序来运行.

#### [#](#堆区管理) 堆区管理

你应该已经在程序设计课上使用过`malloc()`/`free()`库函数, 它们的作用是在用户程序的堆区中申请/释放一块内存区域. 堆区的使用情况是由libc来进行管理的, 但堆区的大小却需要通过系统调用向操作系统提出更改. 这是因为, 堆区的本质是一片内存区域, 当需要调整堆区大小的时候, 实际上是在调整用户程序可用的内存区域. 事实上, 一个用户程序可用的内存区域是需要经过操作系统的分配和管理的. 想象一下, 如果一个恶意程序可以不经过操作系统的同意, 就随意使用其它程序的内存区域, 将会引起灾难性的后果. 当然, 目前Nanos-lite只是个单任务操作系统, 不存在多个程序的概念. 在PA4中, 你将会对这个问题有更深刻的认识.

调整堆区大小是通过`sbrk()`库函数来实现的, 它的原型是

    void* sbrk(intptr_t increment);
    

用于将用户程序的program break增长`increment`字节, 其中`increment`可为负数. 所谓program break, 就是用户程序的数据段(data segment)结束的位置. 我们知道可执行文件里面有代码段和数据段, 链接的时候`ld`会默认添加一个名为`_end`的符号, 来指示程序的数据段结束的位置. 用户程序开始运行的时候, program break会位于`_end`所指示的位置, 意味着此时堆区的大小为0. `malloc()`被第一次调用的时候, 会通过`sbrk(0)`来查询用户程序当前program break的位置, 之后就可以通过后续的`sbrk()`调用来动态调整用户程序program break的位置了. 当前program break和和其初始值之间的区间就可以作为用户程序的堆区, 由`malloc()`/`free()`进行管理. 注意用户程序不应该直接使用`sbrk()`, 否则将会扰乱`malloc()`/`free()`对堆区的管理记录.

在Navy的Newlib中, `sbrk()`最终会调用`_sbrk()`, 它在`navy-apps/libs/libos/src/syscall.c`中定义. 框架代码让`_sbrk()`总是返回`-1`, 表示堆区调整失败, 事实上, 用户程序在第一次调用`printf()`的时候会尝试通过`malloc()`申请一片缓冲区, 来存放格式化的内容. 若申请失败, 就会逐个字符进行输出. 如果你在Nanos-lite中打开strace, 你会发现用户程序通过`printf()`输出的时候, 确实是逐个字符地调用`write()`来输出的.

但如果堆区总是不可用, Newlib中很多库函数的功能将无法使用, 因此现在你需要实现`_sbrk()`了. 为了实现`_sbrk()`的功能, 我们还需要提供一个用于设置堆区大小的系统调用. 在GNU/Linux中, 这个系统调用是`SYS_brk`, 它接收一个参数`addr`, 用于指示新的program break的位置. `_sbrk()`通过记录的方式来对用户程序的program break位置进行管理, 其工作方式如下:

1.  program break一开始的位置位于`_end`
2.  被调用时, 根据记录的program break位置和参数`increment`, 计算出新program break
3.  通过`SYS_brk`系统调用来让操作系统设置新program break
4.  若`SYS_brk`系统调用成功, 该系统调用会返回`0`, 此时更新之前记录的program break的位置, 并将旧program break的位置作为`_sbrk()`的返回值返回
5.  若该系统调用失败, `_sbrk()`会返回`-1`

上述代码是在用户层的库函数中实现的, 我们还需要在Nanos-lite中实现`SYS_brk`的功能. 由于目前Nanos-lite还是一个单任务操作系统, 空闲的内存都可以让用户程序自由使用, 因此我们只需要让`SYS_brk`系统调用总是返回`0`即可, 表示堆区大小的调整总是成功. 在PA4中, 我们会对这一系统调用进行修改, 实现真正的内存分配.

#### 实现堆区管理

根据上述内容在Nanos-lite中实现`SYS_brk`系统调用, 然后在用户层实现`_sbrk()`. 你可以通过`man 2 sbrk`来查阅libc中`brk()`和`sbrk()`的行为, 另外通过`man 3 end`来查阅如何使用`_end`符号.

需要注意的是, 调试的时候不要在`_sbrk()`中通过`printf()`进行输出, 这是因为`printf()`还是会尝试通过`malloc()`来申请缓冲区, 最终会再次调用`_sbrk()`, 造成死递归. 你可以通过`sprintf()`先把调试信息输出到一个字符串缓冲区中, 然后通过`_write()`进行输出.

如果你的实现正确, 你可以借助strace看到`printf()`不再是逐个字符地通过`write()`进行输出, 而是将格式化完毕的字符串通过一次性进行输出.

#### 缓冲区与系统调用开销

你已经了解系统调用的过程了. 事实上, 如果通过系统调用千辛万苦地陷入操作系统只是为了输出区区一个字符, 那就太不划算了. 于是有了批处理(batching)的技术: 将一些简单的任务累积起来, 然后再一次性进行处理. 缓冲区是批处理技术的核心, libc中的`fread()`和`fwrite()`正是通过缓冲区来将数据累积起来, 然后再通过一次系统调用进行处理. 例如通过一个1024字节的缓冲区, 就可以通过一次系统调用直接输出1024个字符, 而不需要通过1024次系统调用来逐个字符地输出. 显然, 后者的开销比前者大得多.

有兴趣的同学可以在GNU/Linux上编写相应的程序, 来粗略测试一下一次`write()`系统调用的开销, 然后和[这篇文章open in new window](http://arkanis.de/weblog/2017-01-05-measurements-of-system-call-performance-and-overhead)对比一下.

#### printf和换行

我们在PA1的时候提示过大家, 使用`printf()`调试时需要添加`\n`, 现在终于可以解释为什么了: `fwrite()`的实现中有缓冲区, `printf()`打印的字符不一定会马上通过`write()`系统调用输出, 但遇到`\n`时可以强行将缓冲区中的内容进行输出. 有兴趣的同学可以阅读`navy-apps/libs/libc/src/stdio/wbuf.c`, 这个文件实现了缓冲区的功能.

实现了这两个系统调用之后, 原则上所有TRM上能运行的程序, 现在都能在Nanos-lite上运行了. 不过我们目前并没有严格按照AM的API来将相应的系统调用功能暴露给用户程序, 毕竟与AM相比, 对操作系统上运行的程序来说, libc的接口更加广为人们所用, 我们也就不必班门弄斧了.

#### 必答题(需要在实验报告中回答) - hello程序是什么, 它从而何来, 要到哪里去

到此为止, PA中的所有组件已经全部亮相, 整个计算机系统也开始趋于完整. 你也已经在这个自己创造的计算机系统上跑起了hello这个第一个还说得过去的用户程序 (dummy是给大家热身用的, 不算), 好消息是, 我们已经距离运行仙剑奇侠传不远了(下一个阶段就是啦).

不过按照PA的传统, 光是跑起来还是不够的, 你还要明白它究竟怎么跑起来才行. 于是来回答这道必答题吧:

> 我们知道`navy-apps/tests/hello/hello.c`只是一个C源文件, 它会被编译链接成一个ELF文件. 那么, hello程序一开始在哪里? 它是怎么出现内存中的? 为什么会出现在目前的内存位置? 它的第一条指令在哪里? 究竟是怎么执行到它的第一条指令的? hello程序在不断地打印字符串, 每一个字符又是经历了什么才会最终出现在终端上?

上面一口气问了很多问题, 我们想说的是, 这其中蕴含着非常多需要你理解的细节. 我们希望你能够认真整理其中涉及的每一行代码, 然后用自己的语言融会贯通地把这个过程的理解描述清楚, 而不是机械地分点回答这几个问题.

同样地, 上一阶段的必答题"理解穿越时空的旅程"也已经涵盖了一部分内容, 你可以把它的回答包含进来, 但需要描述清楚有差异的地方. 另外, C库中`printf()`到`write()`的过程比较繁琐, 而且也不属于PA的主线内容, 这一部分不必展开回答. 而且你也已经在PA2中实现了自己的`printf()`了, 相信你也不难理解字符串格式化的过程. 如果你对Newlib的实现感兴趣, 你也可以RTFSC.

总之, 扣除C库中`printf()`到`write()`转换的部分, 剩下的代码就是你应该理解透彻的了. 于是, 努力去理解每一行代码吧!

#### 支持多个ELF的ftrace

如果我们想了解C库中`printf()`到`write()`的过程, ftrace将是一个很好的工具. 但我们知道, Nanos-lite和它加载的用户程序是两个独立的ELF文件, 这意味着, 如果我们给NEMU的ftrace指定其中一方的ELF文件, 那么ftrace就无法正确将另一方的地址翻译成正确的函数名. 事实上, 我们可以让NEMU的ftrace支持多个ELF: 如果一个地址不属于某个ELF中的任何一个函数, 那就尝试下一个ELF. 通过这种方式, ftrace就可以同时追踪Nanos-lite和用户程序的函数调用了.

#### 温馨提示

PA3阶段2到此结束.