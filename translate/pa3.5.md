[#](#Brilliant-apps) Brilliant apps
=========================

### [#](#Enriched-runtime-environment) Enriched runtime environment

We have already provided IOE access to the user program through system calls and files, and made some underlying encapsulation through NDL. However, for some more complex programs, it is still difficult to program directly with NDL. In order to better support the development and operation of these complex programs, we need to provide higher level libraries.

#### [#](#Multimedia-library) Multimedia library

In Linux, there are a number of GUI programs developed using the SDL library. There is a miniSDL library in Navy that provides some SDL-compatible APIs so that these GUI programs can be easily ported to Navy. The miniSDL code is located in the `navy-apps/libs/libminiSDL/` directory and consists of six modules:

*   `timer.c`: clock management
*   `event.c`: event handling
*   `video.c`: graphics interface
*   `file.c`: file abstraction
*   `audio.c`: audio playback
*   `general.c`: general functions, including initialization, error management, etc.

We can use NDL to support the underlying implementation of miniSDL, allowing miniSDL to provide more functionality to user programs, so that we can run more complex programs on Navy. The APIs in miniSDL have the same name as SDL, you can [RTFM](https://www.libsdl.org/release/SDL-1.2.15/docs/) to check the behavior of these APIs. Also, most of the APIs in miniSDL are not implemented, so you'd better find a way to be alerted when a program uses an unimplemented API, otherwise you may have trouble understanding the unintended behavior of the resulting complex program.

#### Be sure to understand the behavior of the SDL API via RTFM

We will only give a general overview of what these APIs do in the handout, so be sure to consult the SDL manual to understand their specific behavior.

#### [#](#Fixed-point-arithmetic) Fixed-point arithmetic

Some program logic uses real numbers, and since real computer systems nowadays usually come with FPUs, developers usually choose to use floating point numbers to represent these real numbers. But the floating-point standard is too complex for a teaching-oriented computer system, especially when considering DIY processors: implementing a correct FPU in hardware is a very difficult task for everyone. Therefore, we don't plan to introduce floating point numbers in the whole system of Project-N: NEMU doesn't have an FPU, performing floating point operations in AM is UB, Nanos-lite doesn't consider floating point registers to be part of the context, and Navy doesn't provide a runtime environment for floating point numbers (we define the macro `NO_FLOATING_POINT` when we compile Newlib).

If we can implement the logic of the program in some other way, then all these cool programs will have a chance to run on a processor of your own design. In fact, floating-point numbers are not the only way to represent real numbers, but fixed-point numbers can be implemented as well! And fixed-point arithmetic can be implemented as integer arithmetic, which means that we can implement real-number logic through integer arithmetic instructions without having to introduce FPUs into the hardware to run these programs. Such an arithmetic system is called [fixed-point arithmetic](https://en.wikipedia.org/wiki/Fixed-point_arithmetic).

Navy provides a fixedptc library for fixed-point arithmetic. The fixedptc library defaults to 32-bit integers for real numbers, in the form "24.8" (see `navy-apps/libs/libfixedptc/include/fixedptc.h`), which means that the integer portion of the integer takes up 24 bits, and the fractional portion of the integer takes up 8 bits, which is also assumed to mean that the decimal point of a real number is always fixed to the left of the 8th binary digit. It can also be assumed that the decimal point of real numbers is always fixed to the left of the eighth binary digit. The library defines the type `fixedpt`, which is used to represent fixed-point numbers, and can be seen to be essentially of type `int32_t`.

    31  30                           8          0
    +----+---------------------------+----------+
    |sign|          integer          | fraction |
    +----+---------------------------+----------+
    

Thus, for a real number `a`, its `fixedpt` type represents `A = a * 2^8` (truncating the fractional part of the result). For example, the real numbers `1.2` and `5.6` are approximated by the type `FLOAT`, which is

    1.2 * 2^8 = 307 = 0x133
    +----+---------------------------+----------+
    | 0  |             1             |    33    |
    +----+---------------------------+----------+
    
    
    5.6 * 2^8 = 1433 = 0x599
    +----+---------------------------+----------+
    | 0  |             5             |    99    |
    +----+---------------------------+----------+
    

In fact, the two `fixedpt` type data represent real numbers (truth values) that are：

    0x133 / 2^8 = 1.19921875
    0x599 / 2^8 = 5.59765625
    

For negative real numbers, we use the opposite of the corresponding positive number, e.g. the `fixedpt` type of `-1.2` is expressed as:

    -(1.2 * 2^8) = -0x133 = 0xfffffecd
    

#### Comparing fixedpt with float

Both `fixedpt` and `float` types are 32-bit, and they can represent 2^32 different numbers. However, because of the different representation methods, `fixedpt` and `float` can represent different sets of numbers. Consider the trade-offs implicit in using `fixedpt` to simulate `float`.

Next we consider common operations on `fixedpt` types, assuming that the real numbers `a`, `b` have `fixedpt` representations of `A`, `B` respectively.

*   Since we use integers to represent `fixedpt` types, addition of `fixedpt` types can be done directly with integer addition: `fixedpt` types can be added directly with integer addition: `fixedpt` types can be added directly with integer addition:

    A + B = a * 2^8 + b * 2^8 = (a + b) * 2^8
    

*   Since we use complementary representation of `fixedpt` type data, subtraction of `fixedpt` type can be done by integer subtraction:

    A - B = a * 2^8 - b * 2^8 = (a - b) * 2^8
    

*   The `fixedpt` type of multiplication and division is not the same as addition and subtraction:

    A * B = a * 2^8 * b * 2^8 = (a * b) * 2^16 != (a * b) * 2^8
    

In other words, multiplying two `fixedpt` data directly does not give the same result as the `fixedpt` representation of the product of the two real numbers. In order to get the correct result, we need to adjust the result of the multiplication: just divide the result by `2^8`, and you will get the correct result. Division also requires an adjustment of the result, and how to do it is certainly not difficult for the cleverest of you.

*   If `A = a * 2^8` is considered as a mapping, then the relational operations are order-preserving under this mapping, i.e., `a <= b` if and only if `A <= B`, and therefore the relational operations of the type `fixedpt` can be carried out using the relational operations of the integers.

With these conclusions in mind, it is convenient to use the `fixedpt` type to simulate real number operations. The fixedptc library already provides some common APIs, such as

    float a = 1.2;
    float b = 10;
    int c = 0;
    if (b > 7.9) {
      c = (a + 1) * b / 2.3;
    }
    

Expressed in terms of the `fixedpt` type that is

    fixedpt a = fixedpt_rconst(1.2);
    fixedpt b = fixedpt_fromint(10);
    int c = 0;
    if (b > fixedpt_rconst(7.9)) {
      c = fixedpt_toint(fixedpt_div(fixedpt_mul(a + FIXEDPT_ONE, b), fixedpt_rconst(2.3)));
    }
    

As you can see, we're just mapping real numbers to the fixed-point arithmetic system, and then mapping them back again after we've performed operations on them. If we end up needing an integer (such as `c` in the above example), then we can implement the program's original real logic without introducing floating-point instructions.

#### Fantastic fixedpt\_rconst

Reading the code for `fixedpt_rconst()`, on the face of it, it looks like it has a very obvious floating-point operation, but the compiled result doesn't have any floating-point instructions. Do you know why?

In this way, as long as the range of real numbers used in the program is not very large, and the precision of the calculation is not very high, we can replace the floating-point operation with fixed-point operation, so as to maintain the basic logic of the program while avoiding the introduction of floating-point instructions.

#### Implementing more fixedptc APIs

In order to give you a better understanding of the fixed-point representation, we have removed some of the API implementations in `fixedptc.h` that you need to implement. Regarding `fixedpt_floor()` and `fixedpt_ceil()`, you need to implement them strictly according to the semantics of `floor()` and `ceil()` in `man`, otherwise the behavior of `fixedpt_floor()` instead of `floor()` in your program will differ, and in larger programs such as Xian Jian Qi Zia Zhuan, the differences can be very difficult to understand. Therefore, it is also a good idea to write your own test cases to test your implementation.

#### How to convert a floating point variable to a fixedpt type?

Suppose we have a `void *p` pointer variable, which points to a 32-bit variable, which is essentially of type `float`, and whose truth value falls in the range representable by type `fixedpt`. If we define a new function `fixedpt fixedpt_fromfloat(void *p)`, how do we implement it without introducing floating point instructions?

The fixedptc library also provides fixed-point arithmetic implementations of primitive functions such as `sin`, `cos`, `exp`, `ln`, etc., which is basically sufficient for most programs. However, since the decimal part of `fixedpt` is only 8 bits, the precision of these functions may be very low, but this is sufficient for programs on Navy.

#### [#](#Navy-as-infrastructure) Navy as infrastructure

In PA2, we introduced the `native` architecture in AM, and with the abstraction of the AM API, we can run our programs on `native` first, so that we can effectively distinguish hardware (NEMU) bugs from software bugs. Can we achieve a similar effect in Navy?

The answer is yes, because this is the gift that computers give us as an abstraction layer. The runtime environment provided by Navy consists of libos, libc(Newlib), some special files, and various application-oriented libraries. We refer to the first three as the "OS-related runtime environment", while the application-oriented libraries have little to do with the operating system, and for the purposes of this discussion can even be categorized as Navy applications. Similar to implementing the AM API in AM with Linux native functionality, we can implement the above runtime environment with Linux native functionality to support the same Navy applications to run and test them individually. In this way we decouple the operating system related runtime environment from the Navy application.

We provide a special ISA called `native` in Navy to accomplish this decoupling, which differs from other ISAs in that.

*   Linking bypasses libos and Newlib, allowing applications to link directly to Linux's glibc
*   Special files such as `/dev/events`, `/dev/fb`, etc. are implemented through some Linux native mechanisms (see `navy-apps/libs/libos/src/native.cpp`)
*   Applications compiled to Navy native can be run directly and debugged with gdb (see `navy-apps/scripts/native.mk`), while applications compiled to other ISAs can only be run with Nanos-lite support

Although Navy's `native` and AM's `native` share the same name, their mechanisms are different: systems running on AM native require AM, Nanos-lite, libos, libc, and other abstraction layers to support the above runtime environment, and `ARCH=native` in AM, which corresponds to `ISA=am_native` in Navy. In AM, `ARCH=native`, in Navy the equivalent is `ISA=am_native`; in Navy native, the above runtime environment is directly implemented by Linux native.

You can compile `bmp-test` into Navy native by running `make ISA=native run` from the directory where `bmp-test` is located, and you can debug it by `make ISA=native gdb`. This way you can test all the code in Navy except libos and Newlib (e.g. NDL and miniSDL) separately from the Linux native environment. One exception is Navy's dummy, which triggers a system call directly via `_syscall_()`, which does not run directly on Linux native because it doesn't exist in Linux (or is numbered differently).

#### Miraculous LD\_PRELOAD

`bmp-test` needs to open a file with the path `/share/pictures/projectn.bmp`, but in Linux native, the file corresponding to this path does not exist. But we got `bmp-test` to work, do you know how? If you are interested, you can search for `LD_PRELOAD` on the Internet.

#### Wine, WSL and runtime environment compatibility

We can use Linux native to implement Navy's runtime environment, so that applications in Navy can run on Linux native. So can we implement runtime environments for other operating systems, such as providing a Windows-compatible runtime environment in Linux, so as to support Windows applications running on Linux?

One such project is [Wine](https://www.winehq.org/), which implements Windows-related APIs through the Linux runtime environment. Another project that goes in the opposite direction is [WSL](https://docs.microsoft.com/en-us/windows/wsl/about) , which implements Linux APIs through the Windows runtime environment to support Linux programs on Windows, but WSL also modifies the Windows kernel to provide specialized support for Linux programs. But the full Linux and Windows runtimes are so complex that some programs with complex runtime dependencies have struggled to run well on Wine or WSL, so much so that WSL2 abandoned the "runtime compatibility" approach in favor of a virtual machine approach to running Linux perfectly. Navy's runtime environment, on the other hand, is very simple and can be implemented in less than 300 lines of `native.cpp`, but if you understand the concepts involved, you'll understand how technologies like WSL work around you.

### [#](#Applications-in-navy) Applications in navy

With these libraries, we can run many more programs in Navy. Running Xian Jian Qi Xia Zhuan requires a lot of implementation, so let's run some simple programs to test your implementation.

#### [#](#nslider-nju-slider) NSlider (NJU Slider)

NSlider is the simplest presentable application in Navy, which is a slide player that supports page turning. In the 2nd Longxin Cup Competition in 2018, the Nanjing University team realized the goal of "defending the final round of the competition by playing the slideshow on a full-stack computer system built by themselves" by running NSlider on their own implementation of a chaotic processor.

Now you can also run NSlider on your own system, but first you need to implement the `SDL_UpdateRect()` API. SDL's drawing module introduces the notion of a `Surface`, which can be thought of as a canvas with many properties, as described in the `Surface` structure, which can learn more about it via RTFM. `SDL_UpdateRect()` is used to synchronize a specified rectangular area of the canvas to the screen.

#### Run NSlider

We provide a script to convert a PDF version of a 4:3 slide show into a BMP image and copy it to `navy-apps/fsimg/`. You need to provide a PDF file that meets the conditions, and then refer to the appropriate README file to operate. But you may encounter some problems in the conversion, please solve the problem yourself.

Then implement `SDL_UpdateRect()` in miniSDL, if your implementation is correct, the first slide will be displayed when running NSlider. You are probably new to the SDL API, for this you will also need RTFM, and RTFSC to understand the behavior of existing code.

#### Note the size of the ramdisk image

By having the contents of the ramdisk image linked to the Nanos-lite data segment, and loading the user program near memory location `0x3000000` (x86) or `0x83000000` (mips32 or riscv32), there is an implicit assumption that the size of the ramdisk image must not be larger than 48MB. If this assumption is not met, the contents of the ramdisk may be overwritten, causing incomprehensible errors. Therefore you need to be careful about the size of the ramdisk image and not put too many files in it.

#### Run NSlider(2)

Implement `SDL_WaitEvent()` in miniSDL, which is used to wait for an event. You need to encapsulate the events provided in NDL into SDL events and return them to the application, you can read the NSlider code to understand the format of SDL events. Once this is done correctly, you can page through the NSlider, please refer to the RTFSC for how to do this.

#### [#](#menu-Booting-menu) MENU Booting menu

The boot menu is another program with a simpler behavior, it displays a menu where the user can choose which program to run. In order to run it, you also need to implement two drawing-related APIs in miniSDL.

*   `SDL_FillRect()`: fill the specified rectangular area of the canvas with the specified color
*   `SDL_BlitSurface()`: copies a specified rectangular area from one canvas to a specified location on another canvas

The boot menu also displays some English fonts, the information of these fonts is stored in BDF format, Navy provides a libbdf library to parse the BDF format, generate the pixel information of the corresponding characters, and encapsulate it into SDL's `Surface`. After implementing `SDL_BlitSurface()`, we can easily output the pixel information of the string on the screen.

#### Running the boot menu

After implementing the above APIs correctly, you will see a menu that can be paged. However, you will get an error when trying to select a menu item, because the menu requires some system calls to work. This is because there are some system calls required to make the menu work. We'll explain this below, but for now it's enough to test miniSDL with the boot menu.

#### [#](#nterm-nju-terminal) NTerm (NJU Terminal)

NTerm is an emulated terminal, which implements the basic functions of a terminal, including typing characters, backtracking, and fetching commands, etc. NTerm is usually used in conjunction with a shell. Commands obtained from the terminal will be passed to the shell for processing, and the shell will output the information to the terminal. NTerm comes with a very simple built-in shell (see `builtin-sh.cpp`), which ignores all commands by default. NTerm can also communicate with external programs, but this is beyond the scope of ICS and we will not use this feature in PA.

In order to run NTerm, you also need to implement two APIs from miniSDL:

*   `SDL_GetTicks()`: it is exactly the same as `NDL_GetTicks()`
*   `SDL_PollEvent()`: it differs from `SDL_WaitEvent()` in that if there are no current events, it immediately returns

#### Run NTerm

Once you have implemented the above APIs correctly, you will see NTerm's cursor blinking once per second and you will be able to type characters. In order for NTerm to start other programs, you need to implement some system calls, which are described below.

#### Implementing the built-in echo command

Parsing commands in the built-in shell is very similar to parsing commands in the simple debugger you implemented in PA1, and the standard library functions are already available in Navy's Newlib, so if you're interested, you can implement a built-in `echo` command.

#### [#](#flappy-bird) Flappy Bird

Netizen developed a Flappy Bird game based on the SDL library [sdlbird](https://github.com/CecilHarvey/sdlbird), and we easily ported it to Navy. Running `make init` in the `navy-apps/apps/bird/` directory will clone the ported project from github. The ported project will still run on Linux native: just run `make run` in the `navy-apps/apps/bird/repo/` directory (you may need to install some libraries, please STFW). This way of running doesn't link any libraries in Navy, so you'll still hear some sound effects, and you can even play the game by clicking the mouse.

In order to run Flappy Bird in Navy, you also need to implement an API from another library SDL\_image: `IMG_Load()`. This library is based on the image decoding library in [stb project](https://github.com/nothings/stb), and is used to encapsulate the decoded pixels into SDL's `Surface` structure, so that the application can easily display the image on the screen. The above API takes a path to an image file and returns the pixel information encapsulated into an SDL `Surface` structure. One implementation of this API is as follows:

1.  Open the file with libc file operations, and get the size of the file
2.  Request a memory interval with size of buf
3.  Reads the entire file into buf
4.  With buf and size as arguments, call `STBIMG_LoadFromMemory()`, which returns a pointer to the `SDL_Surface` structure
5.  Close the file, freeing the requested memory
6.  Returns a pointer to the `SDL_Surface` structure

#### Run Flappy Bird

Implement `IMG_Load()` to run Flappy Bird in Navy. This is essentially an exercise in file manipulation. Also, Flappy Bird uses a default screen height of 400 pixels, but NEMU's screen height defaults to 300 pixels, so in order to run Flappy Bird on NEMU, you'll need to change `SCREEN_HEIGHT` in `navy-apps/apps/bird/repo/include/Video.h` to 300. 

Flappy Bird also tries to turn on the sound card to play sound effects by default. miniSDL will return 0 or `NULL` to the audio-related APIs by default, and the program will assume that the corresponding operation has failed, but it can still run without sound effects.

In addition, Flappy Bird is a good program to read: it doesn't require much background knowledge, and it's easy to familiarize yourself with the rules of the game, and then understand how the game's effects are implemented in code.

#### Application of "The Computer as a Layer of Abstraction": Porting and Testing

When we port the game, we run it in four environments in order:

*   Pure Linux native: nothing to do with Project-N components, to ensure that the game itself actually works correctly. After changing the version of the library or modifying the game code, it will be tested on Linux native.
*   Navy native: Replace Linux native libraries with Navy libraries to test if the game works correctly with Navy libraries.
*   Native in AM: Replaced Linux system calls and glibc with Nanos-lite, libos and Newlib to test if the game runs correctly with Nanos-lite and its runtime environment.
*   NEMU: Use NEMU to replace the real hardware, test if the game can run correctly under the support of NEMU.

In this way, we can quickly locate the level of abstraction where the bug is located. We can do this thanks to the conclusion that a computer is a layer of abstraction: we can replace parts of a layer of abstraction with a reliable implementation, test the unreliable implementation of one layer of abstraction independently, and then replace the unreliable implementations of the other layers of abstraction one by one and test them. However, this requires that you write portable code, otherwise you won't be able to support the replacement of abstraction layers.

#### [#](#pal-Xian-Jian-Qi-Xia-Zhuan) PAL (Xian Jian Qi Xia Zhuan)

The original Xian Jian Qi Xia Zhuan was developed for Windows, so it doesn't run on GNU/Linux (do you know why?) , nor on Navy-apps. , nor does it run on Navy-apps. We have developed a cross-platform Xian Jian Qi Xia Zhuan based on the SDL library, called [SDLPAL](https://github.com/SDLPAL/sdlpal). We've ported SDLPAL to Navy, running `make init` in the `navy-apps/apps/pal/` directory will clone the ported project from github. Like Flappy Bird, this ported project will still work on Linux native: extract the data files for Xian Jian Qi Xia Zhuan (we posted a link to them in the course announcement) and put them in the `repo/data/` directory, and run `make run` in the `repo/` directory, which will maximize the window to play the game. However, we have changed the audio sampling rate `SampleRate` to `11025` in the `sdlpal.cfg` configuration file, this is to make the game run smoother in Navy, if you have a higher sound quality requirement, you can temporarily change it back to `44100` in Linux native. More information can be found in the README.

#### I'm not a student at NJU, how can I get the data files for PAL (Xian Jian Qi Xia Zhuan)?

Since the data files are copyrighted by the game company, we can't disclose them. However, as a classic game with 25 years of history, you should be able to find it through STFW.

In addition, you need to create the configuration file `sdlpal.cfg` and add the following:

    OPLSampleRate=11025
    SampleRate=11025
    WindowHeight=200
    WindowWidth=320
    

For more information read `repo/docs/README.md` and `repo/docs/sdlpal.cfg.example`.

In order to run Xian Jian Qi Xia Zhuan in Navy, you'll also need to make enhancements to the drawing-related APIs in miniSDL. Specifically, as a game from the 1990s, the drawing is done in 8-bit per pixel, rather than the 32-bit `00RRGGBB` that is commonly used today. These 8 bits are not the actual colors, but the subscript index of an array called "palette", which holds the 32-bit colors. In code form, it is

    // The 32-bit color information is now stored directly in the pixel array
    uint32_t color_xy = pixels[x][y];
    
    // The pixel array in Xian Jian Qi Xia Zhuan stores the 8-bit palette subscripts
    // This subscript is used to index the color palette to get the 32-bit color information
    uint32_t pal_color_xy = palette[pixels[x][y]];
    

The code in Fairy Sword and Wonderland creates 8-bit pixel `Surface` structures, which are processed by the corresponding APIs. Therefore, you need to add support for these 8-bit `Surfaces` to the miniSDL API.

#### Run Xian Jian Qi Xia Zhuan

Add support for 8-bit pixel format to the drawing API in miniSDL. Once this is implemented correctly, you will be able to see the game screen. In order to do this, you will need to implement other APIs, so it's up to you to find out which ones you need to implement. Once implemented, you will be able to run Fairy Fencer in your own NEMU! Please read [here](https://baike.baidu.com/item/%E4%BB%99%E5%89%91%E5%A5%87%E4%BE%A0%E4%BC%A0/5129500#5) for the game operation.

You can test your implementation by performing various operations in the game. The data file we provided contains some game archives, the scenarios in each of the 5 archives are as follows, which can be used for different tests:

1.  Enemy-free labyrinth of organs
2.  Plot without animation
3.  Plot with animation
4.  Labyrinths that have entered the enemy's field of vision
5.  Labyrinths not in enemy view

![pal](/docs/assets/Pal.558e6b6d.png)

#### How does the frame work for Xian Jian Qi Xia Zhuan?

We discussed the basic framework of a game in PA2, so try reading through the code of Legend of the Immortal Sword and Chivalry to find out what functions implement the basic framework. If you can find it, it may help you to debug the game. There is a lot of code in Legend of the Immortal Sword, but you don't need to read a lot of code to answer this question.

#### Scripting engine for Immortal Sword and Sorcery

In `navy-apps/apps/pal/repo/src/game/script.c` there is a function `PAL_InterpretInstruction()`, try to get a general idea of what this function does and how it behaves. Then take a wild guess, how did the developers of Fairy Sword and Wonderland develop the game? Do you have a new understanding of "game engine"?

#### Secret techniques that are no longer mysterious

There are a number of secret techniques circulating on the Internet about the Xian Jian Qi Xia Zhuan, and some of them are as follows.

1.  Many people go to Auntie Yun's place to get money three times, in fact, once you get the money box will be full! You take a money to buy a sword to the money to only a thousand, and then go to the Taoist priest, do not go upstairs, go to the shopkeeper to buy wine, buy a few more times you will find that the money is not used up
2.  keep using the Qiankun Throw (money must be more than 5,000 Wen) until the property is less than 5,000 Wen, the money will skyrocket to the upper limit, so there will be endless money.
3.  when Li Yi Yi level reached 99, use 5~10 gold silkworm king, experience points run out again, and upgrade experience required will be changed back to the initial 5~10 levels of experience value, then go to fight the enemy or use the gold silkworm king to upgrade, you can learn Ling Er's spell (from the five qi towards the yuan); up to level 199 and then use 5~10 gold silkworm king, experience points run out again, the required experience is also very low, you can learn Yue Ru's spell (from the five qi towards the yuan). After level 199, use 5~10 Golden Silkworm Kings, and then run out of experience points, the required upgrade experience is also very low, and you can learn Yue Ru's spells (starting from Yi Yang Finger); after level 299, use 10~30 Golden Silkworm Kings, and then continue to upgrade, and then you can learn Anu's spells (starting from Ants Eroding Elephants).

Assuming that these secret techniques were not intended by the game makers, please try to explain why they work.

#### [#](#am-kernels) am-kernels

You've already run some applications on AM in PA2, and we can easily run them on Navy as well. In fact, AM can run on any environment that supports the implementation of the AM API. There is a libam library in Navy that implements the AM API. The `navy-apps/apps/am-kernels/Makefile` will add libam to the list of links, so that AM APIs called by AM applications will be linked to libam, and these APIs will be implemented by Navy's runtime environment, so that we can run various AM applications on Navy.

#### Implementing AM on Navy

Implement TRM and IOE in libam, then run some AM applications on Navy. The above Makefile compiles coremark, dhrystone and typing games into Navy, but you need to check that the `AM_KERNELS_PATH` variable in it is correct first. You can specify what to compile with `ALL` as you did with `cpu-tests`, e.g. `make ISA=native ALL=coremark run` or `make ISA=x86 ALL=typing-game install`.

#### Running microbench in Navy

Try to compile microbench into Navy and run it, you should find a runtime error, try to analyze the reason.

#### [#](#fceux) FCEUX

With the implementation of libam, FCEUX can also run on Navy.

#### Run FCEUX

In order to compile successfully, you may need to modify the `FCEUX_PATH` variable in the Makefile so that it points to the correct path. Also, we turn off sound when compiling FCEUX via Navy, so you don't need to implement sound card related abstractions in libam.

#### How to run Nanos-lite on Navy?

Since it's possible to run AM-based FCEUX on Navy, it's not impossible to run Nanos-lite on Navy just to show off. Thinking about it, what else do we need if we want to implement CTE on Navy?

#### [#](#oslab0) oslab0

The beauty of AM is not only the ease of supporting the architecture, but also the ease of adding new applications. Your seniors wrote some AM-based games in their OS classes, and since their APIs haven't changed, we can easily port those games to PA. Of course you can do the same for next semester's OS class.

We collected some game in

    https://github.com/NJU-ProjectN/oslab0-collection
    

You can get the game code by `make init` in the `navy-apps/apps/oslab0/` directory. You can compile them into AM and run them, see the relevant README. Alternatively you can compile them into Navy, e.g. by running `make ISA=native ALL=161220016` in the `navy-apps/apps/oslab0/` directory.

#### A game born in the "future".

Try to run the game written by the students on Navy, please refer to the corresponding README for the description and operation of the game.

#### RTFSC???

You may be thinking: wow, won't I have some great code for next semester's oslab0? Well, we've done something special with the released code. While frustrated, think about this: if you had to implement this special treatment, how would you do it? Is it similar to the expression evaluation in PA1?

#### [#](#nplayer-nju-player) NPlayer (NJU Player)

#### This section is optional

Pre-task: Implementing a sound card in PA2.

NPlayer is a music player (maybe with video support in the future), which can be thought of as a cut-down version of MPlayer on Linux, with support for volume adjustment and audio visualization. You have already implemented the sound card device in PA2, and provided the corresponding IOE abstraction in AM. In order to make the sound card available to programs on Navy, we need to provide some functionality in Navy's runtime environment, which is very similar to the process of implementing drawing-related functionality.

The audio-related runtime environment consists of the following.

*   Device files. The Nanos-lite and Navy conventions provide the following device files:
    *   `/dev/sb`: The device file needs to support write operations that allow an application to write decoded audio data to the sound card's stream buffer and play it back, but does not support `lseek` because the audio data stream does not exist after it is played back, so there is no notion of a "location". In addition, writes to the device are blocking, and if the sound card does not have enough free slots in the stream buffer, the write operation will wait until the audio data has been completely written to the stream buffer before returning.
    *   `/dev/sbctl`: This device file is used to control and query the status of the sound card. To initialize the sound card device, the application needs to write 3 `int` integers of 12 bytes at a time, the 3 integers will be interpreted as `freq`, `channels`, `samples`, to initialize the sound card device; To query the status of the sound card device. The application can read out an `int` integer indicating the number of free bytes in the current stream buffer of the sound card device. The device does not support `lseek`.
*   NDL API. NDL encapsulates the above audio-related device files and provides the following API.

    // Turn on the audio function, initialize the sound card device
    void NDL_OpenAudio(int freq, int channels, int samples);
    
    // Turning off the audio function
    void NDL_CloseAudio();
    
    // Play audio data of length `len` bytes in buffer `buf`, return the number of bytes of audio data successfully played
    int NDL_PlayAudio(void *buf, int len);
    
    // Returns the number of free bytes in the current sound card device stream buffer
    int NDL_QueryAudio();
    

*   The miniSDL API. miniSDL further encapsulates the above NDL API by providing the following functionality:

    // Turns on the audio function and initializes the sound card device according to the members of `*desired`
    // After successful initialization, audio playback is paused
    int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained);
    
    // Close the audio function
    void SDL_CloseAudio();
    
    // Pause/resume audio playback
    void SDL_PauseAudio(int pause_on)
    

These APIs in miniSDL are the same APIs you would use to implement a sound card device in PA2's NEMU, and their exact behavior can be RTFM.

One issue that needs to be addressed is how to implement the callback function that is used to load the audio data. This callback function is provided by the application that calls `SDL_OpenAudio()`, and miniSDL needs to call it periodically to get new audio data to write to the stream buffer. In order to realize the above functionality of the callback function, we need to solve the following problems:

1.  How often is the callback function called? This can be calculated from the parameters provided by the application in the `SDL_AudioSpec` structure. Specifically, `freq` is the frequency of samples per second, and `samples` is the number of samples that the callback function requests from the application to fill at a time, so that the interval at which miniSDL calls the callback function can be calculated.
    
2.  How to make miniSDL callback function periodically? In Linux there is a notification mechanism called "[signal](https://en.wikipedia.org/wiki/Signal_(IPC))", based on the signal mechanism can realize the function of timer (similar to an alarm clock), after a certain period of time can notify the application. However, it is very complicated to implement the signaling mechanism in Nanos-lite and Navy, so Nanos-lite does not provide a notification mechanism similar to the signaling mechanism. In order to achieve the effect of "calling the callback function periodically" in the absence of a notification mechanism, miniSDL can only proactively query "if it's time to call the callback function next". Therefore, we can implement a helper function called `CallbackHelper()` with the following behavior.
    
    *   Query the current time
    *   If the current time is greater than the interval since the last callback function was called, then call the callback function, otherwise return directly
    *   If the callback function is called, update the "time of last call"
    
    From now on, we just need to call `CallbackHelper()` as often as possible, so that we can call the callback function in time. To do this, we can insert `CallbackHelper()` into some APIs in miniSDL that will be called frequently by the application. It's not perfect, but it's a workable approach.
    

Once miniSDL has called the callback function to get the new audio data, it can be played via the NDL API. However, by convention, writing to `/dev/sb` is blocking, and it's better to avoid writing too much audio data into the stream buffer and waiting for it, as the time spent waiting would be better spent running the program. Therefore, we can check the current free space in the stream buffer, and make sure that the length of the audio data we fetch from the callback function does not exceed the free space, so that we can avoid waiting.

With these features in place, we are ready to run NPlayer. In addition to calling miniSDL, NPlayer also calls a library called `vorbis`, which is based on the OGG audio decoding library in [stb project](https://github.com/nothings/stb), and can decode an OGG audio file into PCM format audio data.

#### Run NPlayer

After implementing the above audio related functions, try to run NPlayer in Navy. NPlayer will play a complete "Little Star" by default. The volume can be adjusted during playback, as described in the RTFSC.

We also recommend you to read the code of NPlayer, it is a very simple audio player implemented in less than 150 lines of code. For more information about the `vorbis` library API, read the documentation in `navy-apps/libs/libvorbis/include/vorbis.h`.

#### Play your favorite music

Since Navy's library doesn't provide decoders for other audio formats, NPlayer can only play music in OGG format at the moment. However, you can convert your favorite music to OGG format by `ffmpeg`, put it into `navy-apps/fsimg/` directory, and let NPlayer play it.

#### [#](#pal-with-music-and-sound-effects) PAL (with music and sound effects)

The music for Xian Jian Qi Xia Zhuan uses the company's customized RIX format, and SDLPAL already has an audio decoder for the RIX format. However, in order to play the music successfully on Navy, you need to solve two more problems.

The first problem is related to the initialization of the RIX decoder. The decoder uses a library called `Adplug` (see `navy-apps/apps/pal/repo/src/sound/adplug/`), written in C++, which defines some global objects. For global objects, constructor calls need to be supported by the runtime environment, but Navy's default runtime environment does not provide such support.

To help you further understand this, Navy has prepared a test `cpp-test`. What this test program does is very simple: it defines a class in the code, outputs in the constructor and destructor, and defines a global object from this class. Running it directly on Navy's native, you can see that the program runs in the order constructor -> `main()` -> destructor, because Navy's native links to Linux's glibc, which provides a runtime environment that already supports the construction and destruction of global objects. However, if you run it through Nanos-lite, you will find that the program does not call the constructor and destructor, which leaves the members of the global object in an uninitialized state, and the program accesses the global object with unintended results.

In fact, the C++ standard specifies that "whether or not a global object's constructor is called before the execution of the main() function" is compiler implementation-defined behavior, and g++ wraps the initialization of the global object's constructor in an auxiliary function of type `void (*)(void)`, and then fills in the address of this helper function in a section called `.init_array`. This special section can be thought of as an array of pointers to functions of type `void (*)(void)`, which are used to collect functions that need to be executed before the `main()` function is executed. This way, the CRT can traverse the array and call these functions one by one.

#### Getting the runtime environment to support C++ global object initialization

Newlib already contains a function `__libc_init_array()` (defined in `navy-apps/libs/libc/src/misc/init.c`) that iterates over the above arrays, but the runtime environment of the framework code doesn't call it. You only need to call this function before calling `main()`. Run `cpp-test` through Nanos-lite, and if you've implemented it correctly, you'll see that the constructor executes before the `main()` function.

#### Understand the process of calling the global object constructor.

Try to read the code of the `__libc_init_array()` function above, and combine it with the results of `objdump` and `readelf` to understand how the compiler, linker and runtime environment help each other in realizing the "global object constructor call". To see the contents of the `.init_array` section, you need to add the `-D` parameter to `objdump`.

The second problem you'll need to solve in order to get Xian Jian Qi Xia Zhuan to play music successfully on Navy is the reentry of callback functions. In order for miniSDL to call the callback function as promptly as possible, we call `CallbackHelper()` in some of miniSDL's common APIs. But if the callback function calls these APIs again, it will result in dead recursion. One way to solve this problem is to use a flag to indicate whether the current function call is a reentrant or not, and return it if it is.

#### Run Xian Jian Qi Xia Zhuan with music and sound effects

Solve the above reentry problem, and you'll be able to play music in Xian Jian Qi Xia Zhuan.

#### [#](#flappy-bird-with-sound-effects) Flappy Bird (with sound effects)

Flappy Bird's sound playback requires the implementation of three other audio-related APIs in miniSDL:

    // Open the WAV file pointed to by `file` and parse it, filling in the spec with the relevant format
    // and request a piece of memory with the same total length as the audio data, read the audio data from the WAV file into the requested memory,
    // return the first address of the memory via audio_buf, and the number of bytes of audio data via audio_len.
    SDL_AudioSpec *SDL_LoadWAV(const char *file, SDL_AudioSpec *spec, uint8_t **audio_buf, uint32_t *audio_len);
    
    // Free the memory requested through SDL_LoadWAV()
    void SDL_FreeWAV(uint8_t *audio_buf);
    
    // Mix the `len` bytes of audio data in buffer `src` into another buffer `dst` at `volume` volume
    void SDL_MixAudio(uint8_t *dst, uint8_t *src, uint32_t len, int volume);
    

In order to implement `SDL_LoadWAV()`, you need to know the [WAV file format](http://soundfile.sapp.org/doc/WaveFormat/). The relationship between PCM and WAV is very close to the relationship between BIN and ELF: we play PCM audio data directly in PA2, and a WAV file can be seen as a combination of PCM audio data and some organizational information, and the process of parsing a WAV is to read out this information in the header of the WAV file. This process is very similar to your previous ELF loader implementation. Also, WAV files support compression of audio data, but the WAV files used in PA are uncompressed PCM, so you don't need to recognize and deal with compression.

Finally, let's take a look at `SDL_MixAudio()`, which is used to mix two pieces of audio data in order to play them at the same time. Before mixing, it is also possible to adjust the volume of one of the pieces of audio data. As we know, sound is a superposition of several sine waves, and PCM encoding is the sampling and quantization of the superposition curve. Since the volume is proportional to the amplitude of the curve, adjusting the volume is a proportional adjustment of the value of each sample point. In `navy-apps/libs/libminiSDL/include/sdl-audio.h`, we define the maximum volume `SDL_MIX_MAXVOLUME`, and if the `volume` parameter is 1/4 of the `SDL_MIX_MAXVOLUME` parameter, it means that the audio volume will be adjusted to 1/4 of the original volume. To mix two pieces of audio, the curves of the two pieces of audio are overlaid directly on top of each other. However, after the overlay there is a trimming process, which for the 16-bit signed number format results in a maximum value of `32767` and a minimum value of `-32768`, in order to prevent overflow of the overlayed data from distorting the audio (e.g., samples above the x-axis on the curve may become below the x-axis due to overflow). Once this is understood, it is easy to implement `SDL_MixAudio()`.

#### Running Flappy Bird with sound effects

Implement the above API to run Flappy Bird with sound effects in Navy.

[#](#Infrastructure-3) Infrastructure(3)
--------------------

If your Xian Jian Qi Xia Zhuan is not running correctly, you should be able to quickly pinpoint the level of the bug with the help of the different levels of native. If it's a hardware bug, you may be in despair: DiffTest is too slow, especially if it's based on QEMU! What can be done to speed up DiffTest?

### [#](#Free-switching-difftest-mode) Free-switching difftest mode

Currently, DiffTest starts at the beginning, but if the bug is triggered a long time later, then there is no need to start the DiffTest at the beginning. If we suspect that the bug was triggered in a function, then we would prefer that the DUT first runs in normal mode to that function, then turns on DiffTest mode, and then enters that function. This way, we save a lot of unnecessary comparison overhead up front.

In order to realize this function, the key is to enter DiffTest mode at some point in the DUT's operation. An important prerequisite for entering DiffTest mode is to keep the state of the DUT and the REF the same, otherwise the results of the comparison will be meaningless. Once again, we are referring to the concept of state, which you are familiar with: the state of a computer is the state of the timing logic components of the computer. So, if we set the REF's registers and memory to be the same as the DUT's before entering DiffTest mode, they can be compared from an identical state.

In order to control whether the DUT is in DiffTest mode or not, we also need to add the following two commands to the simple debugger.

*   The `detach` command is used to exit DiffTest mode, after which all commands executed by the DUT will no longer be compared to the REF. The implementation is very simple, just let `difftest_step()`, `difftest_skip_dut()` and `difftest_skip_ref()` return directly.
*   The `attach` command is used to enter DiffTest mode, after which all instructions executed by the DUT will be compared with the REF one by one. To do this, you also need to synchronize the contents of the physical memory in the DUT to the corresponding memory intervals in the REF, and synchronize the DUT's register status to the REF as well. In particular, if you choose x86, you need to bypass the memory area around `0x7c00` in the REF. This is because the REF will have GDT-related code around `0x7c00`, and overwriting this code will prevent the REF from running in protected mode, which will make it impossible to run a subsequent DiffTest. In fact, we only need to synchronize `[0x100000, PMEM_SIZE]` is enough, because the program running in NEMU will not use the memory space in `[0, 0x100000)`.

In this way, you can turn on DiffTest when the client program is running at a target location by:

1.  Remove the `-b` parameter for running NEMU, so that we can type commands before the client program starts running.
2.  type the `detach` command to exit DiffTest mode
3.  let the client program run in normal mode to the target location through single-step execution, watchpoints, breakpoints, and so on.
4.  type the `attach` command to enter DiffTest mode, note that setting up the REF memory will take about tens of seconds.
5.  After that, you can continue to run the client program in DiffTest mode.

However, the above approach leaves something to be desired, specifically, we need to deal with some special registers that are also part of the machine state. In the case of x86, for example, we also need to deal with the EFLAGS and IDTR registers, otherwise an inconsistent EFLAGS will cause the next `jcc` or `setcc` instruction to be executed in the REF with unintended results, and an inconsistent IDTR will cause a system call executed in the REF to crash because it cannot find the correct target location. One of the challenges here is that some of the registers in the REF are difficult to set directly, e.g., the GDB protocol that communicates with QEMU does not define how to access the IDTR. However, DiffTest provides an API that solves this problem: we can copy a sequence of instructions to free memory in the REF with `difftest_memcpy_from_dut()`, then point the REF's pc to the sequence with `difftest_setregs()`, then use `difftest_exec()` to set the REF's pc to the sequence, and `difftest_exec()` to set the REF's pc to the sequence with `difftest_exec()`. In this way, we can have the REF execute arbitrary programs, for example, we can have the REF execute the `lidt` instruction, which indirectly sets the IDTR. The EFLAGS register can be set by executing the `popf` instruction.

#### Implement a DiffTest that can be switched freely

Based on the above, add `detach` and `attach` commands to the simple debugger to realize the free switching between normal mode and DiffTest mode.

The above text basically introduces the idea of implementation clearly, if you encounter specific problems, try to analyze and solve them yourself.

### [#](#Snapshots) Snapshots

Even further, it is not necessary to execute NEMU from scratch every time. We can save the state of the NEMU to a file, like the archive system in Xian Jian Qi Xia Zhuan, and then restore the NEMU to that state directly from the file to continue execution later. In the virtualization world, this mechanism has a special name, called [snapshot](https://en.wikipedia.org/wiki/Virtualization#Snapshots). If you're using a virtual machine as a PA, this term should be familiar to you. Implementing snapshots in NEMU is a simple matter of adding the following command to the simple debugger.

*   `save [path]`, save the current state of the NEMU to the file indicated by `path`
*   `load [path]`, restore the state of NEMU from the file indicated by the `path`

#### Snapshots in NEMU

We've emphasized the state of NEMU countless times, so go ahead and implement it. Also, since we may execute NEMU in different directories, it is recommended that when using snapshots, you indicate the snapshot file by an absolute path.

[#](#Showcase your batch system) Showcase your batch system
-------------------------

At the end of PA3, you'll be adding some simple functionality to Nanos-lite to demonstrate your batch system.

You've already executed the boot menu and NTerm on Navy, but neither of them supports executing other programs. This is because "executing other programs" requires a new system call, `SYS_execve`, which ends the current program and starts a specified program. This system call is special in that it does not return to the current program if it is executed successfully, see `man execve` for more information. To implement this system call, you just need to call `naive_uload()` in the corresponding system call handler. For now, we only need to care about `filename`, and the `argv` and `envp` arguments can be ignored for now.

#### Boot menu to run other programs

You need to implement the `SYS_execve` system call to run other programs from the boot menu. You've already implemented many system calls, so I won't bore you with the details.

#### Showcase your batch system

With the boot menu program, it's easy to implement a somewhat decent batch system. All you need to do is modify the implementation of `SYS_exit` so that it calls `SYS_execve` to run `/bin/menu` again, instead of calling `halt()` to end the whole system. This way, at the end of a user program, the operating system will automatically run the boot menu program again, allowing the user to select a new program to run.

As the number of applications grows, using the boot menu to run a program becomes less convenient: you need to keep adding new applications to the boot menu. A more convenient way to run these programs is through NTerm, where you just type the path to the program, e.g. `/bin/pal`.

#### Showcase your batch system(2)

Implement command parsing in NTerm's built-in shell, calling `execve()` with the typed command as an argument. Then make NTerm the first program started by Nanos-lite, and modify the implementation of `SYS_exit` so that it runs `/bin/nterm` again. We don't support passing arguments at the moment, so you can ignore the command arguments for now.

Typing the full path to a command can be tedious. Recall that when we use `ls`, we don't need to type `/bin/ls`. This is because the `PATH` environment variable is defined on the system, and you can read about the behavior with `man execvp`. We can also make the built-in shell in NTerm support this, you just need to set `PATH=/bin` with the `setenv()` function, and then call `execvp()` to execute the new program. Calling `setenv()` requires the `overwrite` parameter to be set to `0`, in order to achieve the same effect on Navy native.

#### Adding Environment Variable Support to the Built-in Shell in NTerm

This is a very simple task, you just need to RTFM the behavior of `setenv()` and `execvp()`, and make a few changes to the built-in Shell code, and you'll get a Shell that is very similar to your usual experience.

#### The Ultimate Question

Since time immemorial, computer systems-oriented programs have had an ultimate question:

> When you type `. /hello` to run the Hello World program, what does the computer actually do?

You have implemented a batch system and successfully run other programs through NTerm. Although our batch system has been simplified in many ways, it still retains the essence of the history of computers. Having implemented a batch system, what new insights have you gained into the ultimate question?

#### 添加开机音乐

你可以准备一段时长几秒钟的音乐(例如某著名的XP开机音乐), 在NTerm中播放它, 这样系统启动进入NTerm的时候就会自动播放这段音乐. 播放音乐的实现可以参考NPlayer的代码.

到这里为止, 我们基本上实现了一个"现代风"的批处理系统了: 我们刚才运行的开机菜单MENU, 就类似红白机中类似"100合1"的游戏选择菜单; 而NTerm的行为也和我们平时使用的终端和Shell非常接近. 重要的是, 这一切都是你亲手构建的: NEMU, AM, Nanos-lite, Navy的运行时环境, 最后到应用程序, "计算机是个抽象层"这一宏观视角已经完全展现在你的眼前, 你终于理解像仙剑奇侠传这样的复杂程序, 是如何经过计算机系统的层层抽象, 最终分解成最基本的硬件操作, 以状态机的方式在硬件上运行. 当你了解到这一真相并为之感到震撼的时候, PA让大家明白"程序如何在计算机上运行"的终极目标也已经实现大半了.

#### 必答题 - 理解计算机系统

*   理解上下文结构体的前世今生 (见PA3.1阶段)
    
*   理解穿越时空的旅程 (见PA3.1阶段)
    
*   hello程序是什么, 它从而何来, 要到哪里去 (见PA3.2阶段)
    
*   仙剑奇侠传究竟如何运行 运行仙剑奇侠传时会播放启动动画, 动画里仙鹤在群山中飞过. 这一动画是通过`navy-apps/apps/pal/repo/src/main.c`中的`PAL_SplashScreen()`函数播放的. 阅读这一函数, 可以得知仙鹤的像素信息存放在数据文件`mgo.mkf`中. 请回答以下问题: 库函数, libos, Nanos-lite, AM, NEMU是如何相互协助, 来帮助仙剑奇侠传的代码从`mgo.mkf`文件中读出仙鹤的像素信息, 并且更新到屏幕上? 换一种PA的经典问法: 这个过程究竟经历了些什么? (Hint: 合理使用各种trace工具, 可以帮助你更容易地理解仙剑奇侠传的行为)
    

#### Kind tips

This is the end of PA3. Please prepare the lab report (don't forget to answer the mandatory questions in the lab report), then place the lab report file named `student.pdf` in the project directory, and execute `make submit` to submit the project to the specified website.