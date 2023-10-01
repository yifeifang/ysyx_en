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

riscv32提供`ecall`指令作为自陷指令, 并提供一个mtvec寄存器来存放异常入口地址. 为了保存程序当前的状态, riscv32提供了一些特殊的系统寄存器, 叫控制状态寄存器(CSR寄存器). 在PA中, 我们只使用如下3个CSR寄存器:

*   mepc寄存器 - 存放触发异常的PC
*   mstatus寄存器 - 存放处理器的状态
*   mcause寄存器 - 存放触发异常的原因

riscv32触发异常后硬件的响应过程如下:

1.  将当前PC值保存到mepc寄存器
2.  在mcause寄存器中设置异常号
3.  从mtvec寄存器中取出异常入口地址
4.  跳转到异常入口地址

* * *

需要注意的是, 上述保存程序状态以及跳转到异常入口地址的工作, 都是硬件自动完成的, 不需要程序员编写指令来完成相应的内容. 事实上, 这只是一个简化后的过程, 在真实的计算机上还要处理很多细节问题, 比如x86和riscv32的特权级切换等, 在这里我们就不深究了. ISA手册中还记录了处理器对中断号和异常号的分配情况, 并列出了各种异常的详细解释, 需要了解的时候可以进行查阅.

#### 特殊的原因? (建议二周目思考)

这些程序状态(x86的eflags, cs, eip; mips32的epc, status, cause; riscv32的mepc, mstatus, mcause)必须由硬件来保存吗? 能否通过软件来保存? 为什么?

由于异常入口地址是硬件和操作系统约定好的, 接下来的处理过程将会由操作系统来接管, 操作系统将视情况决定是否终止当前程序的运行(例如触发段错误的程序将会被杀死). 若决定无需杀死当前程序, 等到异常处理结束之后, 就根据之前保存的信息恢复程序的状态, 并从异常处理过程中返回到程序触发异常之前的状态. 具体地:

*   x86通过`iret`指令从异常处理过程中返回, 它将栈顶的三个元素来依次解释成eip, cs, eflags, 并恢复它们.
*   mips32通过`eret`指令从异常处理过程中返回, 它将清除status寄存器中的异常标志, 并根据epc寄存器恢复PC.
*   riscv32通过`mret`指令从异常处理过程中返回, 它将根据mepc寄存器恢复PC.

### [#](#状态机视角下的异常响应机制) 状态机视角下的异常响应机制

程序是个`S = <R, M>`的状态机, 我们之前已经讨论过在TRM和IOE中这个状态机的具体行为. 如果要给计算机添加异常响应机制, 我们又应该如何对这个状态机进行扩充呢?

首先当然是对`R`的扩充, 除了PC和通用寄存器之外, 还需要添加上文提到的一些特殊寄存器. 我们不妨把这些寄存器称为系统寄存器(System Register), 因为这些寄存器的作用都是和系统功能相关的, 平时进行计算的时候不会使用. 扩充之后的寄存器可以表示为`R = {GPR, PC, SR}`. 异常响应机制和内存无关, 因此我们无需对`M`的含义进行修改.

对状态转移的扩充就比较有趣了. 我们之前都是认为程序执行的每一条指令都会成功, 从而状态机会根据指令的语义进行状态转移. 添加异常响应机制之后, 我们允许一条指令的执行会"失败". 为了描述指令执行失败的行为, 我们可以假设CPU有一条虚构的指令`raise_intr`, 执行这条虚构指令的行为就是上文提到的异常响应过程. 显然, 这一行为是可以用状态机视角来描述的, 例如在riscv32中可以表示成:

    SR[mepc] <- PC
    SR[mcause] <- 一个描述失败原因的号码
    PC <- SR[mtvec]
    

有了这条虚构的指令, 我们就可以从状态机视角来理解异常响应的行为了: 如果一条指令执行成功, 其行为和之前介绍的TRM与IOE相同; 如果一条指令执行失败, 其行为等价于执行了虚构的`raise_intr`指令.

那么, "一条指令的执行是否会失败"这件事是不是确定性的呢? 显然这取决于"失败"的定义, 例如除0就是"除法指令的第二个操作数为0", 非法指令可以定义成"不属于ISA手册描述范围的指令", 而自陷指令可以认为是一种特殊的无条件失败. 不同的ISA手册都有各自对"失败"的定义, 例如RISC-V手册就不认为除0是一种失败, 因此即使除数为0, 在RISC-V处理器中这条指令也会按照指令手册的描述来执行.

事实上, 我们可以把这些失败的条件表示成一个函数`fex: S -> {0, 1}`, 给定状态机的任意状态`S`, `fex(S)`都可以唯一表示当前PC指向的指令是否可以成功执行. 于是, 给计算机加入异常响应机制并不会增加系统的不确定性, 这大大降低了我们理解异常响应机制的难度, 同时也让调试不至于太困难: 一个程序运行多次, 还是会在相同的地方抛出相同的异常, 从而进行相同的状态转移 (IOE的输入指令会引入一些不确定性, 但目前还是在我们能控制的范围内).

![cte](/docs/assets/cte.08895f5f.png)

最后, 异常响应机制的加入还伴随着一些系统指令的添加, 例如x86的`lidt`, `iret`, riscv32的`csrrw`, `mret`等. 这些指令除了用于专门对状态机中的`SR`进行操作之外, 它们本质上和TRM的计算指令没有太大区别, 因此它们的行为也不难理解.

[#](#将上下文管理抽象成cte) 将上下文管理抽象成CTE
-------------------------------

我们刚才提到了程序的状态, 在操作系统中有一个等价的术语, 叫"上下文". 因此, 硬件提供的上述在操作系统和用户程序之间切换执行流的功能, 在操作系统看来, 都可以划入上下文管理的一部分.

与IOE一样, 上下文管理的具体实现也是架构相关的: 例如上文提到, x86/mips32/riscv32中分别通过`int`/`syscall`/`ecall`指令来进行自陷, `native`中甚至可以通过一些神奇的库函数来模拟相应的功能; 而上下文的具体内容, 在不同的架构上也显然不一样(比如寄存器就已经不一样了). 于是, 我们可以将上下文管理的功能划入到AM的一类新的API中, 名字叫CTE(ConText Extension).

接下来的问题是, 如何将不同架构的上下文管理功能抽象成统一的API呢? 换句话说, 我们需要思考, 操作系统的处理过程其实需要哪些信息?

*   首先当然是引发这次执行流切换的原因, 是程序除0, 非法指令, 还是触发断点, 又或者是程序自愿陷入操作系统? 根据不同的原因, 操作系统都会进行不同的处理.
*   然后就是程序的上下文了, 在处理过程中, 操作系统可能会读出上下文中的一些寄存器, 根据它们的信息来进行进一步的处理. 例如操作系统读出PC所指向的非法指令, 看看其是否能被模拟执行. 事实上, 通过这些上下文, 操作系统还能实现一些神奇的功能, 你将会在PA4中了解更详细的信息.

#### 用软件模拟指令

在一些嵌入式场景中, 处理器对低功耗的要求非常严格, 很多时候都会去掉浮点处理单元FPU来节省功耗. 这时候如果软件要执行一条浮点指令, 处理器就会抛出一个非法指令的异常. 有了异常响应机制, 我们就可以在异常处理的过程中模拟这条非法指令的执行了, 原理和PA2中的指令执行过程非常类似. 在不带FPU的各种处理器中, 都可以通过这种方式来执行浮点指令.

#### 在AM中执行浮点指令是UB

换句话说, AM的运行时环境不支持浮点数. 这听上去太暴力了. 之所以这样决定, 是因为IEEE 754是个工业级标准, 为了形式化逻辑上的soundness和completeness, 标准里面可能会有各种奇怪的设定, 例如不同的舍入方式, inf和nan的引入等等, 作为教学其实没有必要去理解它们的所有细节; 但如果要去实现一个正确的FPU, 你就没法摆脱这些细节了.

和PA2中的定点指令不同, 浮点指令在PA中用到的场合比较少, 而且我们有别的方式可以绕开, 所以就怎么简单怎么来了, 于是就UB吧. 当然, 如果你感兴趣, 你也可以考虑实现一个简化版的FPU. 毕竟是UB, 如果你的FPU行为正确, 也不算违反规定.

#### 另一个UB

另一种你可能会碰到的UB是栈溢出, 对, 就是stackoverflow的那个. 检测栈溢出需要一个更强大的运行时环境, AM肯定是无能为力了, 于是就UB吧.

不过, AM究竟给程序提供了多大的栈空间呢? 事实上, 如果你在PA2的时候尝试努力了解每一处细节, 你已经知道这个问题的答案了; 如果你没有, 你需要反思一下自己了, 还是认真RTFSC吧.

所以, 我们只要把这两点信息抽象成一种统一的表示方式, 就可以定义出CTE的API了. 对于切换原因, 我们只需要定义一种统一的描述方式即可. CTE定义了名为"事件"的如下数据结构(见`abstract-machine/am/include/am.h`):

    typedef struct Event {
      enum { ... } event;
      uintptr_t cause, ref;
      const char *msg;
    } Event;
    

其中`event`表示事件编号, `cause`和`ref`是一些描述事件的补充信息, `msg`是事件信息字符串, 我们在PA中只会用到`event`. 然后, 我们只要定义一些统一的事件编号(上述枚举常量), 让每个架构在实现各自的CTE API时, 都统一通过上述结构体来描述执行流切换的原因, 就可以实现切换原因的抽象了.

对于上下文, 我们只能将描述上下文的结构体类型名统一成`Context`, 至于其中的具体内容, 就无法进一步进行抽象了. 这主要是因为不同架构之间上下文信息的差异过大, 比如mips32有32个通用寄存器, 就从这一点来看, mips32和x86的`Context`注定是无法抽象成完全统一的结构的. 所以在AM中, `Context`的具体成员也是由不同的架构自己定义的, 比如`x86-nemu`的`Context`结构体在`abstract-machine/am/include/arch/x86-nemu.h`中定义. 因此, 在操作系统中对`Context`成员的直接引用, 都属于架构相关的行为, 会损坏操作系统的可移植性. 不过大多数情况下, 操作系统并不需要单独访问`Context`结构中的成员. CTE也提供了一些的接口, 来让操作系统在必要的时候访问它们, 从而保证操作系统的相关代码与架构无关.

最后还有另外两个统一的API:

*   `bool cte_init(Context* (*handler)(Event ev, Context *ctx))`用于进行CTE相关的初始化操作. 其中它还接受一个来自操作系统的事件处理回调函数的指针, 当发生事件时, CTE将会把事件和相关的上下文作为参数, 来调用这个回调函数, 交由操作系统进行后续处理.
*   `void yield()`用于进行自陷操作, 会触发一个编号为`EVENT_YIELD`事件. 不同的ISA会使用不同的自陷指令来触发自陷操作, 具体实现请RTFSC.

CTE中还有其它的API, 目前不使用, 故暂不介绍它们.

接下来, 我们将尝试在Nanos-lite中触发一次自陷操作, 来梳理过程中的细节.

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