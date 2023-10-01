[#](#A-journey-through-time-and-space) A journey through time and space
=====================

With a powerful hardware protection mechanism, user programs will not be able to switch the execution flow to any code of the operating system. But in order to implement the simplest operating system, the hardware also needs to provide an execution flow switching method that can limit the entry. This method is a self-trap instruction. After the program executes the self-trap instruction, it will fall into a jump target preset by the operating system. This jump target is also called the exception entry address.

This process is part of the ISA specification and is called the interrupt/exception response mechanism. Most ISAs do not distinguish between CPU exceptions and traps, or even hardware interrupts that will be introduced at the end of PA4, but respond to them uniformly . At present, we have not added hardware interrupts, so let's call this mechanism simply "exception response mechanism".

### [#](#x86) x86

x86 provides the `int` instruction as a self-trap instruction, but its exception response mechanism is more complicated than other ISAs. In x86, the above exception entry address is indicated by the gate descriptor. The door descriptor is an 8-byte structure, which contains a lot of detailed information. We have simplified the structure of the door descriptor in NEMU, retaining only the existence bit P and offset OFFSET:

       31                23                15                7                0
      +-----------------+-----------------+---+-------------------------------+
      |           OFFSET 31..16           | P |          Don't care           |4
      +-----------------------------------+---+-------------------------------+
      |             Don't care            |           OFFSET 15..0            |0
      +-----------------+-----------------+-----------------+-----------------+
    

The P bit is used to indicate whether this gate descriptor is valid, and OFFSET is used to indicate the exception entry address. With the gate descriptor, the user program can only jump to the location specified by OFFSET in the gate descriptor, and can no longer jump to any code of the operating system as desired.

In order to facilitate the management of each gate descriptor, x86 specifically interprets a certain piece of data in the memory into an array, called IDT (Interrupt Descriptor Table, interrupt descriptor table). One element of the array is a gate descriptor. In order to find a gate descriptor from the array, we also need an index. For CPU exceptions, this index is generated internally by the CPU (e.g. divide-by-zero exception is exception 0), or given by the `int` instruction (e.g. `int $0x80`). Finally, in order to find the IDT in memory, x86 uses the IDTR register to store the first address and length of the IDT. The operating system code prepares the IDT in advance, and then executes a special instruction `lidt` to set the first address and length of the IDT in the IDTR. This exception response mechanism can work smoothly. Now everything is ready, when the program executes the trap instruction or triggers an exception, the CPU will jump to the exception entry address according to the set IDT:

               |               |
               |   Entry Point |<----+
               |               |     |
               |               |     |
               |               |     |
               +---------------+     |
               |               |     |
               |               |     |
               |               |     |
               +---------------+     |
               |offset |       |     |
               |-------+-------|     |
               |       | offset|-----+
      index--->+---------------+
               |               |
               |Gate Descriptor|
               |               |
        IDT--->+---------------+
               |               |
               |               |
    

However, we may still need to return to the current state of the program to continue execution in the future, such as a breakpoint exception triggered by `int3`. This means that we need to save the current state of the program when responding to an exception. Therefore, the response process of the hardware after an exception is triggered is as follows:

1.  Read the first address of IDT from IDTR
2.  Index in the IDT based on the exception number and find a gate descriptor
3.  Combine the offset fields in the door descriptor into the exception entry address
4.  Push the values of eflags, cs (code segment register), and eip (that is, PC) registers onto the stack in sequence.
5.  Jump to the exception entry address

In a harmonious computer society, most gate descriptors cannot be used by user processes at will, otherwise malicious programs can deceive the operating system through the `int` instruction. For example, a malicious program executes `int $0x2` to falsely report a power outage and disrupt the normal operation of other processes. Therefore, executing the `int` instruction also requires a privilege level check, but this protection mechanism is not implemented in PA. We will not discuss the specific checking rules. If you need to know more, just RTFM.

### [#](#mips32) mips32

mips32 provides the `syscall` instruction as a self-trap instruction, and its working process is very simple. According to mips32 convention, the above-mentioned exception entry address is always `0x80000180`. In order to save the current status of the program, mips32 provides some special system registers. These registers are located in co-processor 0 (Co-Processor 0), so they are also called CP0 registers. In PA, we only use the following three CP0 registers :

*   epc register - stores the PC that triggered the exception
*   status register - stores the status of the processor
*   cause register - stores the reason for triggering the exception

The hardware response process after mips32 triggers an exception is as follows:

1.  Save current PC value to epc register
2.  Set the exception number in the cause register
3.  Set the exception flag in the status register to cause the processor to enter kernel mode
4.  Jump to `0x80000180`

### [#](#riscv32) riscv32

riscv32 provides the `ecall` instruction as a self-trap instruction, and provides an mtvec register to store the exception entry address. In order to save the current status of the program, riscv32 provides some special system registers called control status registers (CSR registers). In PA, we only use the following 3 CSR registers:

*   mepc register - stores the PC that triggered the exception
*   mstatus register - stores the status of the processor
*   mcause register - stores the reason for triggering the exception

The hardware response process after riscv32 triggers an exception is as follows:

1.  Save current PC value to mepc register
2.  Set the exception number in the mcause register
3.  Get the exception entry address from the mtvec register
4.  Jump to the exception entry address

* * *

It should be noted that the above-mentioned work of saving the program state and jumping to the exception entry address is automatically completed by the hardware, and the programmer does not need to write instructions to complete the corresponding content. In fact, this is just a simplified process. There are many details that need to be dealt with on a real computer, such as privilege level switching between x86 and riscv32, etc. We will not go into details here. The ISA manual also records the allocation of interrupt numbers and exception numbers by the processor, and lists detailed explanations of various exceptions, which you can refer to when you need to know more.

#### Special reason? (It is recommended to think about it in the second trail)

Do these program states (eflags, cs, eip of x86; epc, status, cause of mips32; mepc, mstatus, mcause of riscv32) have to be saved by hardware? Can they be saved by software? Why?

Since the exception entry address is agreed between the hardware and the operating system, the subsequent processing will be taken over by the operating system. The operating system will decide whether to terminate the current program based on the situation (for example, the program that triggers a segmentation fault will be killed). If it is decided that there is no need to kill the current program, wait until the exception handling is completed, restore the state of the program based on the previously saved information, and return from the exception handling process to the state before the program triggered the exception. Specifically:

*   x86 returns from the exception handling process through the `iret` instruction, which interprets the three elements on the top of the stack into eip, cs, eflags, and restores them.
*   mips32 returns from the exception handling process through the `eret` instruction, which will clear the exception flag in the status register and restore the PC according to the epc register.
*   riscv32 returns from the exception handling process through the `mret` instruction, which will restore the PC according to the mepc register.

### [#](#Exception-response-mechanism-from-the-perspective-of-state-machine) Exception response mechanism from the perspective of state machine

The program is a state machine with `S = <R, M>`. We have discussed the specific behavior of this state machine in TRM and IOE before. If we want to add an exception response mechanism to the computer, how should we expand this state machine?

The first is of course the expansion of `R`. In addition to the PC and general registers, some special registers mentioned above also need to be added. We might as well call these registers system registers (System Register), because the functions of these registers are related to system functions and are not used during normal calculations. The expanded register can be expressed as `R = {GPR, PC, SR}`. The exception response mechanism has nothing to do with memory, so we do not need to modify the meaning of `M`.

The expansion of state transfer is more interesting. We used to think that every instruction executed by the program will succeed, so the state machine will transfer the state according to the semantics of the instruction. After adding the exception response mechanism, we allow the execution of an instruction to "fail". In order to describe the behavior of instruction execution failure, we can assume that the CPU has a fictitious instruction `raise_intr`, and the behavior of executing this fictitious instruction is the exception response process mentioned above. Obviously, this behavior can be described from a state machine perspective, for example in riscv32 it can be expressed as:

    SR[mepc] <- PC
    SR[mcause] <- a number describing the reason for the failure
    PC <- SR[mtvec]
    

With this fictitious instruction, we can understand the behavior of exception responses from a state machine perspective: If an instruction is executed successfully, its behavior is the same as the TRM and IOE introduced previously; if an instruction fails, its behavior is equivalent to executing the fictional `raise_intr` instruction.

So, is "whether the execution of an instruction will fail" deterministic? Obviously this depends on the definition of "failure". For example, division by 0 means "the second operand of the division instruction is 0", which is an illegal instruction. It can be defined as "instructions that do not belong to the description scope of the ISA manual", and the self-trap instruction can be considered as a special unconditional failure. Different ISA manuals have their own definitions of "failure", for example, the RISC-V manual does not consider division by 0 is a failure, so even if the divider is 0, this instruction will be executed as described in the instruction manual in the RISC-V processor.

In fact, we can express these failure conditions as a function `fex: S -> {0, 1}`. Given any state `S` of the state machine, `fex(S)` can uniquely indicate whether the instruction pointed to by the current PC can be successfully executed. Therefore, adding an exception response mechanism to the computer will not increase the uncertainty of the system. This greatly reduces the difficulty for us to understand the exception response mechanism, and also makes debugging not too difficult: if a program is run multiple times, the same exception will still be thrown in the same place, resulting in the same state transition (IOE input instructions will introduce some uncertainty, but it is still within our control).

![cte](/docs/assets/cte.08895f5f.png)

Finally, the addition of the exception response mechanism is also accompanied by the addition of some system instructions, such as x86's `lidt`, `iret`, riscv32's `csrrw`, `mret`, etc. Except that these instructions are used to specifically operate `SR` in the state machine, they are essentially not much different from the calculation instructions of TRM, so their behavior is not difficult to understand.

[#](#Abstract-context-management-into-CTE) Abstract context management into CTE
-------------------------------

We just mentioned the state of the program, and there is an equivalent term in the operating system called "context". Therefore, the above-mentioned function provided by the hardware to switch the execution flow between the operating system and the user program, from the perspective of the operating system, All can be classified as part of context management.

Like IOE, the specific implementation of context management is also architecture-related: for example, as mentioned above, in x86/mips32/riscv32, the `int`/`syscall`/`ecall` instructions are used to trap, and in `native`, the corresponding functions can even be simulated through some magical library functions; the specific content of context is obviously different in different architectures (for example, registers are already different). Therefore, we can classify the context management function into a new API of AM called CTE (ConText Extension).

The next question is, how to abstract the context management functions of different architectures into a unified API? In other words, we need to think about what information the operating system actually needs for its processing?

*   First of all, of course, what caused this execution flow switch? Was it the program dividing by 0, an illegal instruction, triggering a breakpoint, or was the program voluntarily trapped in the operating system? Depending on the reasons, the operating system will handle it differently.
*   Then there is the context of the program. During the processing, the operating system may read out some registers in the context and perform further processing based on their information. For example, the operating system reads the illegal instruction pointed to by the PC to see if it can be simulated and executed. In fact, through these contexts, the operating system can also implement some magical functions, which you will learn more about in PA4.

#### Simulate instructions using software

In some embedded scenarios, the processor has very strict requirements for low power consumption, and the floating point processing unit FPU is often removed to save power consumption. At this time, if the software wants to execute a floating point instruction, the processor will throw an illegal instruction exception. With the exception response mechanism, we can simulate the execution of this illegal instruction during the exception handling process. The principle is very similar to the instruction execution process in PA2. Floating point instructions can be executed in this way in various processors without FPU.

#### Executing floating point instructions in AM is UB (Undefined Behavior)

In other words, AM's runtime environment does not support floating point numbers. This sounds too violent. The reason for this decision is that IEEE 754 is an industrial standard. In order to formalize logical soundness and completeness, there may be various strange settings in the standard, such as different rounding methods, the introduction of inf and nan, etc. It is not necessary to understand all their details as a tutorial; but if you want to implement a correct FPU, you cannot get rid of these details.

Different from the fixed-point instructions in PA2, floating-point instructions are rarely used in PA, and we have other ways to get around it, so we just do it as simple as possible, so let’s do UB. Of course, if you are interested, you can also consider implementing a simplified version of FPU. After all, it is UB, and if your FPU behaves correctly, it does not violate the regulations.

#### Another UB

Another type of UB you may encounter is stack overflow, yes, the one on stackoverflow. Detecting stack overflow requires a more powerful runtime environment, and AM is definitely powerless, so let's use UB.

However, how much stack space does AM provide to the program? In fact, if you tried to understand every detail in PA2, you already know the answer to this question; if you don't, you need to reflect on yourself and take RTFSC seriously.

Therefore, as long as we abstract these two pieces of information into a unified representation, we can define the API of CTE. For the cause of event, we only need to define a unified description method. CTE defines the following data structure named "event" (see `abstract-machine/am/include/am.h`):

    typedef struct Event {
      enum { ... } event;
      uintptr_t cause, ref;
      const char *msg;
    } Event;
    

Among them, `event` represents the event number, `cause` and `ref` are some supplementary information describing the event, `msg` is the event information string, we will only use `event` in PA. Then, we only need to define some unified event numbers (the above-mentioned enumeration constants), so that when each architecture implements its own CTE API, it can uniformly describe the cause for execution flow switching through the above-mentioned structures, so that the abstraction of the switching cause can be achieved.

For context, we can only unify the structure type name that describes the context into `Context`. As for the specific content, we cannot further abstract it. This is mainly because the context information between different architectures is too different. For example, mips32 has 32 general-purpose registers. From this point of view, the `Context` of mips32 and x86 is destined to be unable to be abstracted into a completely unified structure. Therefore, in AM, the specific members of `Context` are also defined by different architectures. For example, the `Context` structure of `x86-nemu` is defined in `abstract-machine/am/include/arch/x86-nemu.h`. Therefore, direct references to `Context` members in the operating system are architecture-related behaviors and will damage the portability of the operating system. However, in most cases, the operating system does not need to access the members in the `Context` structure separately. CTE also provides some interfaces to allow the operating system to access them when necessary, thereby ensuring that the relevant code of the operating system has nothing to do with the architecture.

Finally there are two other unified APIs:

*   `bool cte_init(Context* (*handler)(Event ev, Context *ctx))` used to perform CTE-related initialization operations. It also accepts a pointer to the event processing callback function from the operating system. When an event occurs, CTE will use the event and related context as parameters to call this callback function and leave it to the operating system for subsequent processing.
*   `void yield()` is used to perform a self-trap operation, which will trigger an event numbered `EVENT_YIELD`. Different ISAs will use different self-trap instructions to trigger a self-trap operation. For specific implementation, please RTFSC.

There are other APIs in CTE that are not currently used, so we will not introduce them yet.

Next, we will try to trigger a trap operation in Nanos-lite to sort out the details of the process.

### [#](#设置异常入口地址) 设置异常入口地址

首先是按照ISA的约定来设置异常入口地址, 将来切换执行流时才能跳转到正确的异常入口. 这显然是架构相关的行为, 因此我们把这一行为放入CTE中, 而不是让Nanos-lite直接来设置异常入口地址. 你需要在`nanos-lite/include/common.h`中定义宏`HAS_CTE`, 这样以后, Nanos-lite会多进行一项初始化工作: 调用`init_irq()`函数, 这最终会调用位于`abstract-machine/am/src/$ISA/nemu/cte.c`中的`cte_init()`函数. `cte_init()`函数会做两件事情, 第一件就是设置异常入口地址:

*   对x86来说, 就是要准备一个有意义的IDT
    1.  代码定义了一个结构体数组`idt`, 它的每一个元素是一个门描述符结构体
    2.  在相应的数组元素中填写有意义的门描述符, 例如编号为`0x81`的门描述符中就包含自陷操作的入口地址. 需要注意的是, 框架代码中还是填写了完整的门描述符(包括上文中提到的don't care的域), 这主要是为了进行DiffTest时让KVM也能跳转到正确的入口地址. KVM实现了完整的x86异常响应机制, 如果只填写简化版的门描述符, 代码就无法在其中正确运行. 但我们无需了解其中的细节, 只需要知道代码已经填写了正确的门描述符即可.
    3.  通过`lidt`指令在IDTR中设置`idt`的首地址和长度
*   对于mips32来说, 由于异常入口地址是固定在`0x80000180`, 因此我们需要在`0x80000180`放置一条无条件跳转指令, 使得这一指令的跳转目标是我们希望的真正的异常入口地址即可.
*   对于riscv32来说, 直接将异常入口地址设置到mtvec寄存器中即可.

`cte_init()`函数做的第二件事是注册一个事件处理回调函数, 这个回调函数由Nanos-lite提供, 更多信息会在下文进行介绍.

### [#](#触发自陷操作) 触发自陷操作

为了测试异常入口地址是否已经设置正确, 我们还需要真正触发一次自陷操作. 定义了宏`HAS_CTE`后, Nanos-lite会在`panic()`前调用`yield()`来触发自陷操作. 为了支撑这次自陷操作, 你需要在NEMU中实现`isa_raise_intr()`函数 (在`nemu/src/isa/$ISA/system/intr.c`中定义)来模拟上文提到的异常响应机制.

需要注意的是:

*   PA不涉及特权级的切换, RTFM的时候你不需要关心和特权级切换相关的内容.
*   你需要在自陷指令的实现中调用`isa_raise_intr()`, 而不要把异常响应机制的代码放在自陷指令的helper函数中实现, 因为在后面我们会再次用到`isa_raise_intr()`函数.
*   如果你选择的是x86, 通过IDTR中的地址对IDT进行索引的时候, 需要使用`vaddr_read()`.

#### 实现异常响应机制

你需要实现上文提到的新指令, 并实现`isa_raise_intr()`函数. 然后阅读`cte_init()`的代码, 找出相应的异常入口地址.

实现后, 重新运行Nanos-lite, 如果你发现NEMU确实跳转到你找到的异常入口地址, 说明你的实现正确(NEMU也可能因为触发了未实现指令而终止运行).

#### 让DiffTest支持异常响应机制

为了让DiffTest机制正确工作, 你需要

*   针对x86:
    *   NEMU中不实现分段机制, 没有cs寄存器的概念. 但为了顺利进行DiffTest, 你还是需要在cpu结构体中添加一个cs寄存器, 并在将其初始化为`8`.
    *   由于x86的异常响应机制需要对eflags进行压栈, 你还需要将eflags初始化为`0x2`.
*   针对riscv32, 你需要将mstatus初始化为`0x1800`.
*   针对riscv64, 你需要将mstatus初始化为`0xa00001800`.

### [#](#保存上下文) 保存上下文

成功跳转到异常入口地址之后, 我们就要在软件上开始真正的异常处理过程了. 但是, 进行异常处理的时候不可避免地需要用到通用寄存器, 然而看看现在的通用寄存器, 里面存放的都是执行流切换之前的内容. 这些内容也是上下文的一部分, 如果不保存就覆盖它们, 将来就无法恢复这一上下文了. 但通常硬件并不负责保存它们, 因此需要通过软件代码来保存它们的值. x86提供了`pusha`指令, 用于把通用寄存器的值压栈; 而mips32和riscv32则通过`sw`指令将各个通用寄存器依次压栈.

除了通用寄存器之外, 上下文还包括:

*   触发异常时的PC和处理器状态. 对于x86来说就是eflags, cs和eip, x86的异常响应机制已经将它们保存在堆栈上了; 对于mips32和riscv32来说, 就是epc/mepc和status/mstatus寄存器, 异常响应机制把它们保存在相应的系统寄存器中, 我们还需要将它们从系统寄存器中读出, 然后保存在堆栈上.
*   异常号. 对于x86, 异常号由软件保存; 而对于mips32和riscv32, 异常号已经由硬件保存在cause/mcause寄存器中, 我们还需要将其保存在堆栈上.
*   地址空间. 这是为PA4准备的, 在x86中对应的是`CR3`寄存器, 代码通过一条`pushl $0`指令在堆栈上占位, mips32和riscv32则是将地址空间信息与0号寄存器共用存储空间, 反正0号寄存器的值总是0, 也不需要保存和恢复. 不过目前我们暂时不使用地址空间信息, 你目前可以忽略它们的含义.

#### 异常号的保存

x86通过软件来保存异常号, 没有类似cause的寄存器. mips32和riscv32也可以这样吗? 为什么?

于是, 这些内容构成了完整的上下文信息, 异常处理过程可以根据上下文来诊断并进行处理, 同时, 将来恢复上下文的时候也需要这些信息.

#### 对比异常处理与函数调用

我们知道进行函数调用的时候也需要保存调用者的状态: 返回地址, 以及calling convention中需要调用者保存的寄存器. 而CTE在保存上下文的时候却要保存更多的信息. 尝试对比它们, 并思考两者保存信息不同是什么原因造成的.

接下来代码会调用C函数`__am_irq_handle()`(在`abstract-machine/am/src/$ISA/nemu/cte.c`中定义), 来进行异常的处理.

#### 诡异的x86代码

x86的`trap.S`中有一行`pushl %esp`的代码, 乍看之下其行为十分诡异. 你能结合前后的代码理解它的行为吗? Hint: 程序是个状态机.

#### 重新组织\`Context\`结构体

你的任务如下:

*   实现这一过程中的新指令, 详情请RTFM.
*   理解上下文形成的过程并RTFSC, 然后重新组织`abstract-machine/am/include/arch/$ISA-nemu.h` 中定义的`Context`结构体的成员, 使得这些成员的定义顺序和 `abstract-machine/am/src/$ISA/nemu/trap.S`中构造的上下文保持一致.

需要注意的是, 虽然我们目前暂时不使用上文提到的地址空间信息, 但你在重新组织`Context`结构体时仍然需要正确地处理地址空间信息的位置, 否则你可能会在PA4中遇到难以理解的错误.

实现之后, 你可以在`__am_irq_handle()`中通过`printf`输出上下文`c`的内容, 然后通过简易调试器观察触发自陷时的寄存器状态, 从而检查你的`Context`实现是否正确.

#### 给一些提示吧

"实现新指令"没什么好说的, 你已经在PA2中实现了很多指令了. "重新组织结构体"是一个非常有趣的题目, 如果你不知道要做什么, 不妨从读懂题目开始. 题目大概的意思就是, 根据`trap.S`里面的内容, 来定义`$ISA-nemu.h`里面的一个结构体. `trap.S`明显是汇编代码, 而`$ISA-nemu.h`里面则是一个用C语言定义的结构体. 汇编代码和C语言... 等等, 你好像想起了ICS课本的某些内容...

#### 我乱改一通, 居然过了, 嘿嘿嘿

如果你还抱着这种侥幸心态, 你在PA3中会过得非常痛苦. 事实上, "明白如何正确重新组织结构体"是PA3中非常重要的内容. 所以我们还是加一道必答题吧.

#### 必答题(需要在实验报告中回答) - 理解上下文结构体的前世今生

你会在`__am_irq_handle()`中看到有一个上下文结构指针`c`, `c`指向的上下文结构究竟在哪里? 这个上下文结构又是怎么来的? 具体地, 这个上下文结构有很多成员, 每一个成员究竟在哪里赋值的? `$ISA-nemu.h`, `trap.S`, 上述讲义文字, 以及你刚刚在NEMU中实现的新指令, 这四部分内容又有什么联系?

如果你不是脑袋足够灵光, 还是不要眼睁睁地盯着代码看了, 理解程序的细节行为还是要从状态机视角入手.

### [#](#事件分发) 事件分发

`__am_irq_handle()`的代码会把执行流切换的原因打包成事件, 然后调用在`cte_init()`中注册的事件处理回调函数, 将事件交给Nanos-lite来处理. 在Nanos-lite中, 这一回调函数是`nanos-lite/src/irq.c`中的`do_event()`函数. `do_event()`函数会根据事件类型再次进行分发. 不过我们在这里会触发一个未处理的4号事件:

    [src/irq.c,5,do_event] system panic: Unhandled event ID = 4
    

这是因为CTE的`__am_irq_handle()`函数并未正确识别出自陷事件. 根据`yield()`的定义, `__am_irq_handle()`函数需要将自陷事件打包成编号为`EVENT_YIELD`的事件.

#### 实现正确的事件分发

你需要:

1.  在`__am_irq_handle()`中通过异常号识别出自陷异常, 并打包成编号为`EVENT_YIELD`的自陷事件.
2.  在`do_event()`中识别出自陷事件`EVENT_YIELD`, 然后输出一句话即可, 目前无需进行其它操作.

重新运行Nanos-lite, 如果你的实现正确, 你会看到识别到自陷事件之后输出的信息,

### [#](#恢复上下文) 恢复上下文

代码将会一路返回到`trap.S`的`__am_asm_trap()`中, 接下来的事情就是恢复程序的上下文. `__am_asm_trap()`将根据之前保存的上下文内容, 恢复程序的状态, 最后执行"异常返回指令"返回到程序触发异常之前的状态.

不过这里需要注意之前自陷指令保存的PC, 对于x86的`int`指令, 保存的是指向其下一条指令的PC, 这有点像函数调用; 而对于mips32的`syscall`和riscv32的`ecall`, 保存的是自陷指令的PC, 因此软件需要在适当的地方对保存的PC加上4, 使得将来返回到自陷指令的下一条指令.

#### 从加4操作看CISC和RISC

事实上, 自陷只是其中一种异常类型. 有一种故障类异常, 它们返回的PC和触发异常的PC是同一个, 例如缺页异常, 在系统将故障排除后, 将会重新执行相同的指令进行重试, 因此异常返回的PC无需加4. 所以根据异常类型的不同, 有时候需要加4, 有时候则不需要加.

这时候, 我们就可以考虑这样的一个问题了: 决定要不要加4的, 是硬件还是软件呢? CISC和RISC的做法正好相反, CISC都交给硬件来做, 而RISC则交给软件来做. 思考一下, 这两种方案各有什么取舍? 你认为哪种更合理呢? 为什么?

代码最后会返回到Nanos-lite触发自陷的代码位置, 然后继续执行. 在它看来, 这次时空之旅就好像没有发生过一样.

#### 恢复上下文

你需要实现这一过程中的新指令. 重新运行Nanos-lite, 如果你的实现正确, 你会看到在`do_event()`中输出的信息, 并且最后仍然触发了`main()`函数末尾设置的`panic()`.

#### 必答题(需要在实验报告中回答) - 理解穿越时空的旅程

从Nanos-lite调用`yield()`开始, 到从`yield()`返回的期间, 这一趟旅程具体经历了什么? 软(AM, Nanos-lite)硬(NEMU)件是如何相互协助来完成这趟旅程的? 你需要解释这一过程中的每一处细节, 包括涉及的每一行汇编代码/C代码的行为, 尤其是一些比较关键的指令/变量. 事实上, 上文的必答题"理解上下文结构体的前世今生"已经涵盖了这趟旅程中的一部分, 你可以把它的回答包含进来.

别被"每一行代码"吓到了, 这个过程也就大约50行代码, 要完全理解透彻并不是不可能的. 我们之所以设置这道必答题, 是为了强迫你理解清楚这个过程中的每一处细节. 这一理解是如此重要, 以至于如果你缺少它, 接下来你面对bug几乎是束手无策.

#### mips32延迟槽和异常

我们在PA2中提到, 标准的mips32处理器采用了分支延迟槽技术. 思考一下, 如果标准的mips32处理器在执行延迟槽指令的时候触发了异常, 从异常返回之后可能会造成什么问题? 该如何解决? 尝试RTFM对比你的解决方案.

### [#](#异常处理的踪迹-etrace) 异常处理的踪迹 - etrace

处理器抛出异常也可以反映程序执行的行为, 因此我们也可以记录异常处理的踪迹(exception trace). 你也许认为在CTE中通过`printf()`输出信息也可以达到类似的效果, 但这一方案和在NEMU中实现的etrace还是有如下区别:

*   打开etrace不改变程序的行为(对程序来说是非侵入式的): 你将来可能会遇到一些bug, 当你尝试插入一些`printf()`之后, bug的行为就会发生变化. 对于这样的bug, etrace还是可以帮助你进行诊断, 因为它是在NEMU中输出的, 不会改变程序的行为.
*   etrace也不受程序行为的影响: 如果程序包含一些致命的bug导致无法进入异常处理函数, 那就无法在CTE中调用`printf()`来输出; 在这种情况下, etrace仍然可以正常工作

事实上, QEMU和Spike也实现了类似etrace的功能, 如果在上面运行的系统软件发生错误, 开发者也可以通过这些功能快速地进行bug的定位和诊断.

#### 实现etrace

你已经在NEMU中实现了很多trace工具了, 要实现etrace自然也难不倒你啦.

#### 温馨提示

PA3阶段1到此结束.

[批处理系统](/docs/ics-pa/3.1.html) [用户程序和系统调用](/docs/ics-pa/3.3.html)