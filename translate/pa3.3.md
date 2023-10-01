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

#### Running Hello world on Nanos-lite

Navy provides a `hello` test program (`navy-apps/tests/hello`), which first outputs a sentence via `write()`, and then keeps outputting it via `printf()`.

You need to implement the `write()` system call, and then switch the user program running on Nanos-lite to run as a `hello` program.

#### [#](#Heap-area-management) Heap area management

You should have already used the `malloc()`/`free()` library functions in your programming classes, which are used to request/release an area of memory in the heap of a user program. The heap usage is managed by libc, but the size of the heap needs to be changed by a system call to the operating system. This is because the heap is essentially an area of memory, and when you resize the heap, you are actually resizing the area of memory available to the user program. In fact, the memory area available to a user program is allocated and managed by the operating system. Imagine the disastrous consequences if a malicious program could use other programs' memory without the operating system's consent. Of course, Nanos-lite is currently a single-tasking operating system, and the concept of multiple programs does not exist. In PA4, you will have a better understanding of this issue.

Resizing the heap is accomplished with the `sbrk()` library function, which has the following prototype

    void* sbrk(intptr_t increment);
    

Used to grow the user program's program break by `increment` bytes, where `increment` can be a negative number. A program break is the end of a data segment of a user program. We know that an executable file contains both a code segment and a data segment, and when linking, `ld` adds a symbol called `_end` to indicate the end of the program's data segment. When the user program starts running, the program break will be at the location indicated by `_end`, meaning that the size of the heap is 0. The first time `malloc()` is called, it will query the user program for the current location of the program break by `sbrk(0)`, and then the program break can be dynamically adjusted by subsequent `sbrk()` calls. The interval between the current program break and its initial value can be used as the heap area of the user program, managed by `malloc()`/`free()`. Note that the user program should not use `sbrk()` directly, as this will mess up the `malloc()`/`free()` management of the heap.

In Navy's Newlib, `sbrk()` ends up calling `_sbrk()`, which is defined in `navy-apps/libs/libos/src/syscall.c`. The framework code makes `_sbrk()` always return `-1`, indicating that heap resizing has failed. In fact, the user program tries to claim a buffer for the formatted content with `malloc()` when it first calls `printf()`. If the request fails, it is output character by character. If you open strace in Nanos-lite, you'll see that when the user program outputs via `printf()`, it does call `write()` character by character.

But if the heap is always unavailable, a lot of the functionality of the library functions in Newlib won't be available, so now you need to implement `_sbrk()`. In order to implement `_sbrk()`, we also need to provide a system call that sets the heap size. In GNU/Linux, this system call is `SYS_brk`, which takes one argument, `addr`, and indicates the location of the new program break. `_sbrk()` manages the location of a user program's program break by logging it, and works as follows.

1.  The program break starts at `_end`
2.  When called, a new program break is calculated based on the recorded program break position and the parameter `increment`
3.  Get the operating system to set up a new program break with the `SYS_brk` system call
4.  If the `SYS_brk` system call succeeds, the system call returns `0`, at which point it updates the location of the previously recorded program break and returns the location of the old program break as the return value of `_sbrk()`
5.  If this system call fails, `_sbrk()` returns `-1`

The above code is implemented in a user-level library function, but we also need to implement `SYS_brk` in Nanos-lite. Since Nanos-lite is still a single-tasking operating system, free memory is free for the user program to use, so we just need to make the `SYS_brk` system call always return `0` to indicate that the heap resize is always successful. In PA4, we will modify this system call to enable real memory allocation.

#### Implementing heap area management

Implement the `SYS_brk` system call in Nanos-lite based on the above, and then implement `_sbrk()` at the user level. You can check the behavior of `brk()` and `sbrk()` in libc via `man 2 sbrk`, and how to use the `_end` symbol via `man 3 end`.

Note that when debugging, you should not output from `_sbrk()` via `printf()`, because `printf()` will still try to claim the buffer via `malloc()`, and will end up calling `_sbrk()` again, which will result in a dead recursion. You can use `sprintf()` to output the debugging information to a string buffer first, and then `_write()` to output it.

If your implementation is correct, you can see with strace that `printf()` no longer outputs the string character by character via `write()`, but rather outputs the formatted string all at once.

#### Buffer and System Call Overhead

You already know how system calls work. In fact, it wouldn't be cost-effective to go to all the trouble of getting into the operating system via a system call just to output a single character. Hence the technique of batching: accumulating simple tasks and processing them all at once. Buffers are at the heart of batching, and libc's `fread()` and `fwrite()` use buffers to accumulate data, which is then processed in a single system call. For example, with a 1024-byte buffer, you can output 1024 characters in a single system call, rather than 1024 system calls to output each character. Obviously, the latter is much more expensive than the former.

If you are interested, you can write a program on GNU/Linux to roughly test the overhead of a single `write()` syscall, and then compare it to [this article](http://arkanis.de/weblog/2017-01-05-measurements-of-system-call-performance-and-overhead).

#### printf and newlines

We hinted in PA1 that you need to add `\n` when debugging with `printf()`, and now we can finally explain why: `fwrite()` has a buffer in its implementation, and the characters printed by `printf()` are not necessarily outputted immediately by the `write()` system call, but the contents of the buffer are forced to be output by `\n` when it is encountered. But it is possible to force the contents of the buffer to be output when \n` is encountered. If you are interested, you can read `navy-apps/libs/libc/src/stdio/wbuf.c`, which implements the buffer function.

With the implementation of these two system calls, in principle all programs that can run on TRM can now run on Nanos-lite. However, we do not currently expose the system calls to user programs in strict accordance with the AM API, since the libc interface is more widely available to programs running on the operating system than to AM, and we do not need to show off.

#### Mandatory questions (to be answered in the lab report) - What is the hello program, where does it come from, where does it go?

At this point, all the components of PA have been revealed, and the computer system is starting to become complete. You've run hello, the first decent user program (dummy is for warming up, not counting), on a computer system of your own creation, and the good news is that we're not far from running Xian Jian Qi Xuan Zhuan (that's the next stage).

But in the tradition of PA, it's not enough to just get it up and running, you have to understand how it's going to get up and running. So here's the mandatory question:

> We know that `navy-apps/tests/hello/hello.c` is just a C source file, which is compiled and linked into an ELF file. So, where does the hello program start? How did it get into memory? Why is it in the current memory location? Where is its first instruction? How exactly did it get to its first instruction? The hello program is printing strings over and over again, what does each character go through before it finally appears in the terminal?

That's a lot of questions in one breath, and we'd like to point out that there's a lot of detail here that you need to understand. We want you to carefully analyze each line of code involved, and then describe your understanding of the process in your own words, rather than mechanically answering the questions in points.

Similarly, the mandatory question "Understanding journeys through space and time" from the previous phase has already covered some of this, so you can include it in your answer, but you need to describe the differences. Also, the process of `printf()` to `write()` in the C library is a bit tedious and not part of the main thread of PA, so you don't need to expand on that part of the answer. Besides, you've already implemented your own `printf()` in PA2, so it's not hard for you to understand the string formatting process. If you're interested in the Newlib implementation, you can also RTFSC it.

Anyway, excluding the `printf()` to `write()` conversions in the C library, the rest of the code is what you should understand. So, try to understand every line of code!

#### 支持多个ELF的ftrace

如果我们想了解C库中`printf()`到`write()`的过程, ftrace将是一个很好的工具. 但我们知道, Nanos-lite和它加载的用户程序是两个独立的ELF文件, 这意味着, 如果我们给NEMU的ftrace指定其中一方的ELF文件, 那么ftrace就无法正确将另一方的地址翻译成正确的函数名. 事实上, 我们可以让NEMU的ftrace支持多个ELF: 如果一个地址不属于某个ELF中的任何一个函数, 那就尝试下一个ELF. 通过这种方式, ftrace就可以同时追踪Nanos-lite和用户程序的函数调用了.

#### 温馨提示

PA3阶段2到此结束.