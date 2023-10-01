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

### [#](#Set-exception-entry-address) Set exception entry address

The first is to set the exception entry address according to the ISA convention, so that it can jump to the correct exception entry when switching the execution flow in the future. This is obviously an architecture-related behavior, so we put this behavior into the CTE instead of letting Nanos-lite directly sets the exception entry address. You need to define the macro `HAS_CTE` in `nanos-lite/include/common.h`, so that in the future, Nanos-lite will perform one more initialization work: Call the `init_irq()` function, which ultimately calls the `cte_init()` function located in `abstract-machine/am/src/$ISA/nemu/cte.c`. The `cte_init()` function will do two things. The first is to set the exception entry address:

*   For x86, it is necessary to prepare a meaningful IDT
    1.  The code defines a structure array `idt`, each element of which is a gate descriptor structure
    2.  Fill in the meaningful gate descriptor in the corresponding array element. For example, the gate descriptor numbered `0x81` contains the entry address of the trap operation. It should be noted that the complete gate descriptor (including the don't care fields mentioned above) is still filled in in the framework code. This is mainly to allow KVM to jump to the correct entry address when performing DiffTest. KVM implements a complete x86 exception response mechanism. If you only fill in the simplified version of the gate descriptor, the code will not run correctly in it. But we do not need to know the details, we only need to know that the code has filled in the correct gate descriptor.
    3.  Set the start address and length of `idt` in IDTR through `lidt` command
*   For mips32, since the exception entry address is fixed at `0x80000180`, we need to place an unconditional jump instruction at `0x80000180` so that the jump target of this instruction is the real exception entry address we want.
*   For riscv32, just set the exception entry address directly to the mtvec register.

The second thing the `cte_init()` function does is to register an event handling callback function. This callback function is provided by Nanos-lite. More information will be introduced below.

### [#](#Trigger-a-trap-operation) Trigger a trap operation

In order to test whether the exception entry address has been set correctly, we also need to actually trigger a trap operation. After defining the macro `HAS_CTE`, Nanos-lite will call `yield()` before `panic()` to trigger the self-trap operation. In order to support this self-trap operation, you need to implement the `isa_raise_intr()` function in NEMU (defined in `nemu/src/isa/$ISA/system/intr.c`) to simulate the exception response mentioned mechanism above.

You should notice that:

*   PA does not involve privilege level switching. When RTFM, you do not need to care about privilege level switching.
*   You need to call `isa_raise_intr()` in the implementation of the trap instruction, instead of implementing the exception response mechanism code in the helper function of the trap instruction, because we will use the `isa_raise_intr()` function again later.
*   If you choose x86, you need to use `vaddr_read()` when indexing the IDT through the address in IDTR.

#### Implement exception response mechanism

You need to implement the new instructions mentioned above and implement the `isa_raise_intr()` function. Then read the code of `cte_init()` to find the corresponding exception entry address.

After implementation, re-run Nanos-lite. If you find that NEMU does jump to the exception entry address you found, it means your implementation is correct (NEMU may also terminate the operation because an unimplemented instruction is triggered).

#### Let DiffTest support exception response mechanism

In order for the DiffTest mechanism to work correctly, you need

*   For x86:
    *   NEMU does not implement segmentation mechanism and there is no concept of cs register. But in order to perform DiffTest smoothly, you still need to add a cs register to the cpu structure and initialize it to `8`.
    *   Since the x86 exception response mechanism requires pushing eflags onto the stack, you also need to initialize eflags to `0x2`.
*   For riscv32, you need to initialize mstatus to `0x1800`.
*   For riscv64, you need to initialize mstatus to `0xa00001800`.

### [#](#Save-context) Save context

After successfully jumping to the exception entry address, we will start the real exception handling process in the software. However, general-purpose registers are inevitably needed for exception handling. However, looking at the current general-purpose registers, they contain the contents before the execution flow switch. These contents are also part of the context. If you overwrite them without saving them, the context cannot be restored in the future. But usually the hardware is not responsible for saving them, so software code needs to be used to save their values. x86 provides the `pusha` instruction, which is used to push the value of general-purpose registers onto the stack; while mips32 and riscv32 use the `sw` instruction to push each general-purpose register onto the stack in sequence.

In addition to general-purpose registers, context includes:

*   The PC and processor status when the exception is triggered. For x86, it is eflags, cs and eip. The x86 exception response mechanism has saved them on the stack; for mips32 and riscv32, it is the epc/mepc and status/mstatus registers. The exception response mechanism saves them in the corresponding system registers. We also need to read them from the system registers and save them on the stack.
*   Exception number. For x86, the exception number is saved by software; while for mips32 and riscv32, the exception number has been saved by hardware in the cause/mcause register, and we also need to save it on the stack.
*   Address space. This is prepared for PA4. In x86, it corresponds to the `CR3` register. The code takes up space on the stack through a `pushl $0` instruction, mips32 and riscv32 share the storage space of address space information with register 0. Anyway, the value of register 0 is always 0, and there is no need to save and restore. However, we do not use address space information for the time being, and you can ignore their meaning for now.

#### Save exception number

x86 saves exception numbers through software, and there is no register similar to cause. Can mips32 and riscv32 also do this? Why?

Therefore, these contents constitute complete context information. The exception handling process can diagnose and handle based on the context. At the same time, this information will also be needed when restoring the context in the future.

#### Compare exception handling and function calling

We know that when making a function call, we also need to save the caller's state: the return address, and the registers that the caller needs to save in the calling convention. However, CTE needs to save more information when saving context. Try to compare them and think about the reason why the two save different information.

Next, the code will call the C function `__am_irq_handle()` (defined in `abstract-machine/am/src/$ISA/nemu/cte.c`) to handle exceptions.

#### Weird x86 code

There is a line of code called `pushl %esp` in `trap.S` of x86. At first glance, its behavior is very strange. Can you understand its behavior by combining the preceding and following codes? Hint: The program is a state machine.

#### Reorganize the \`Context\` structure

Your tasks are as follows:

*   Implement new instructions in this process, please RTFM for details.
*   Understand the process of context formation and RTFSC, and then reorganize the members of the `Context` structure defined in `abstract-machine/am/include/arch/$ISA-nemu.h` so that the definition order of these members consistent with the context constructed in `abstract-machine/am/src/$ISA/nemu/trap.S`.

It should be noted that although we are not currently using the address space information mentioned above, you still need to correctly handle the location of the address space information when reorganizing the `Context` structure, otherwise you may encounter incomprehensible problems in PA4.

After implementation, you can output the contents of context `c` through `printf` in `__am_irq_handle()`, and then use the simple debugger to observe the register status when the trap is triggered to check whether your `Context` implementation is correct.

#### Some tips

There is nothing much to say about "Implementing new instructions". You have already implemented many instructions in PA2. "Reorganizing structures" is a very interesting topic. If you don't know what to do, you might as well start by understanding the task. The general meaning of the task is to define a structure in `$ISA-nemu.h` based on the content in `trap.S`. `trap.S` is obviously assembly code, while `$ISA-nemu.h` contains a structure defined in C language. Assembly code and C language... Wait, you seem to remember some content from the ICS textbook...

#### I made some random corrections and actually passed, hahaha

If you still have this kind of luck mentality, you will have a very painful life in PA3. In fact, "understanding how to reorganize structures correctly" is a very important content in PA3. So let's add a required question.

#### Required questions (need to be answered in the lab report) - Understand the past and present life of context structures

You will see a context structure pointer `c` in `__am_irq_handle()`. Where is the context structure pointed to by `c`? Where does this context structure come from? Specifically, this context structure has many members, where is each member assigned? `$ISA-nemu.h`, `trap.S`, the above handout text, and the new instructions you just implemented in NEMU. What is the connection between these four parts?

If you are not smart enough, don't just stare at the code. To understand the detailed behavior of the program, you still have to start from the state machine perspective.

### [#](#Event-distribution) Event distribution

The code of `__am_irq_handle()` will package the cause for execution flow switching into an event, then call the event processing callback function registered in `cte_init()`, and hand the event to Nanos-lite for processing. In Nanos-lite, this callback function is the `do_event()` function in `nanos-lite/src/irq.c`. The `do_event()` function will be distributed again according to the event type. But here we will trigger an unhandled event No. 4:

    [src/irq.c,5,do_event] system panic: Unhandled event ID = 4
    

This is because the `__am_irq_handle()` function of CTE does not correctly identify the self-trap event. According to the definition of `yield()`, the `__am_irq_handle()` function needs to package the self-trap event into an event numbered `EVENT_YIELD`.

#### Implement correct event distribution

You need to:

1.  In `__am_irq_handle()`, the trap exception is identified by the exception number and packaged into a trap event numbered `EVENT_YIELD`.
2.  Identify the self-trapping event `EVENT_YIELD` in `do_event()`, and then output a sentence. No other operations are required at the moment.

Re-run Nanos-lite. If your implementation is correct, you will see the information output after recognizing the trap event.

### [#](#Restore-context) Restore context

The code will return all the way to `__am_asm_trap()` in `trap.S`, and the next thing is to restore the context of the program. `__am_asm_trap()` will restore the state of the program based on the previously saved context content, and finally execute the "exception return instruction" to return to the state before the program triggered the exception.

However, you need to pay attention here to the PC saved by the previous self-trap instruction. For the `int` instruction of x86, the PC pointed to the next instruction is saved, which is a bit like a function call; for `syscall` of mips32 and `ecall` of riscv32, the PC of the self-trap instruction is saved, so the software needs to add 4 to the saved PC in the appropriate place to return to the next instruction of the self-trap instruction in the future.

#### Looking at CISC and RISC from the plus 4 operation

In fact, trapping is just one of the exception types. There is a kind of fault-type exception. The PC they return is the same as the PC that triggered the exception. For example, page missing exception. After the system eliminates the fault, it will re-execute the same instruction and try again. Therefore, the PC returned by the exception does not need to be increased by 4. So depending on the exception type, sometimes you need to add 4, sometimes you don’t need to add it.

At this time, we can consider this question: Is it hardware or software that decides whether to add 4? CISC and RISC are exactly the opposite. CISC leaves it to the hardware, while RISC leaves it to the software. Think about it, what are the trade-offs between these two solutions? Which one do you think is more reasonable? Why?

The code will eventually return to the code location where Nanos-lite triggered the trap, and then continue execution. From its perspective, this time and space journey will be as if it never happened.

#### Restore context

You need to implement the new instructions in this process. Re-run Nanos-lite. If your implementation is correct, you will see the information output in `do_event()`, and finally the `panic()` set at the end of the `main()` function is still triggered.

#### Required questions (need to be answered in the lab report) - Understanding the journey through time and space

From the time Nanos-lite calls `yield()` to the time it returns from `yield()`, what exactly does this journey go through? How do software (AM, Nanos-lite) and hardware (NEMU) assist each other to complete this journey? You need to explain every detail in this process, including the behavior of every line of assembly code/C code involved, especially some of the more critical instructions/variables. In fact, the above required question "Understanding the Past and Present Life of Contextual Structures" already covers part of this journey, and you can include its answer.

Don't be intimidated by "every line of code". This process is only about 50 lines of code. It is not impossible to fully understand it. The reason why we set this mandatory question is to force you to understand every detail of this process. This understanding is so important that if you lack it, you will be almost helpless when facing bugs.

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