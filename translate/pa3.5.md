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

#### 运行NPlayer

实现上述音频相关的功能后, 尝试在Navy中运行NPlayer. NPlayer默认会播放一首完整的"小星星". 播放过程中还可以调整音量, 具体操作可以RTFSC.

我们也建议你阅读NPlayer的代码, 它通过不到150行的代码就实现了一个非常简单的音频播放器. 关于`vorbis`库的API功能, 可以阅读`navy-apps/libs/libvorbis/include/vorbis.h`中的文档.

#### 播放自己喜欢的音乐

由于Navy的库中没有提供其它音频格式的解码器, 目前NPlayer只能播放OGG格式的音乐. 不过你可以通过`ffmpeg`把你喜欢的音乐转换成OGG格式, 放到`navy-apps/fsimg/`目录中, 就可以让NPlayer来播放它了.

#### [#](#pal-带音乐和音效) PAL (带音乐和音效)

仙剑奇侠传的音乐使用的是公司自定义的RIX格式, SDLPAL中已经集成了RIX格式的音频解码器. 不过为了让仙剑奇侠传可以在Navy上成功播放音乐, 你还需要解决以下两个问题.

第一个问题和RIX解码器的初始化有关. 解码器用到了一个叫`Adplug`的库(见`navy-apps/apps/pal/repo/src/sound/adplug/`), 它是使用C++编写的, 其中定义了一些全局对象. 对全局对象来说, 构造函数的调用需要运行时环境的支持, 但Navy的默认运行时环境并没有提供这样的支持.

为了帮助你进一步理解这个问题, Navy准备了一个测试`cpp-test`. 这个测试程序做的事情非常简单: 代码中定义了一个类, 在构造函数和析构函数中进行输出, 并通过这个类定义了一个全局对象. 在Navy的native上直接运行它, 你可以看到程序按照构造函数->`main()`\->析构函数的顺序来运行, 这是因为Navy的native会链接Linux的glibc, 它提供的运行时环境已经支持全局对象的构造和销毁. 但如果你通过Nanos-lite来运行它, 你会发现程序并没有调用构造函数和析构函数, 这样就会使得全局对象中的成员处于未初始化的状态, 程序访问这个全局对象就会造成非预期的结果.

实际上, C++的标准规定, "全局对象的构造函数调用是否位于main()函数执行之前" 是和编译器的实现相关的(implementation-defined behavior), g++会把全局对象构造函数的初始化包装成一个类型为`void (*)(void)`的辅助函数, 然后把这个辅助函数的地址填写到一个名为`.init_array`的节(section)中. 这个特殊的节可以看做是一个`void (*)(void)`类型的函数指针数组, 专门用于收集那些需要在`main()`函数执行之前执行的函数. 这样以后, CRT就可以遍历这个数组, 逐个调用这些函数了.

#### 让运行时环境支持C++全局对象的初始化

Newlib中已经包含了一个遍历上述数组的函数`__libc_init_array()` (在`navy-apps/libs/libc/src/misc/init.c`中定义), 但框架代码的运行时环境并没有调用它, 你只需要在调用`main()`之前调用这个函数即可. 通过Nanos-lite来运行`cpp-test`, 如果你的实现正确, 你会看到构造函数会比`main()`函数先执行.

#### 理解全局对象构造函数的调用过程

尝试阅读上述`__libc_init_array()`函数的代码, 并结合`objdump`和`readelf`的结果, 理解编译器, 链接器和运行时环境是如何相互协助, 从而实现"全局对象构造函数的调用"这一功能的. 为了看到`.init_array`节的内容, 你需要给`objdump`添加`-D`参数.

为了让仙剑奇侠传可以在Navy上成功播放音乐, 你还需要解决的第二个问题是回调函数的重入. 为了让miniSDL尽可能及时地调用回调函数, 我们在miniSDL的一些常用API中调用`CallbackHelper()`. 但如果回调函数又调用了这些API, 就会导致死递归. 解决问题的一种方式是通过一个标志来指示当前的函数调用是否属于重入, 若是则直接返回.

#### 运行带音乐和音效的仙剑奇侠传

解决上述重入问题, 你就可以在仙剑奇侠传中播放音乐了.

#### [#](#flappy-bird-带音效) Flappy Bird (带音效)

Flappy Bird的音效播放需要实现miniSDL中另外3个和音频相关的API:

    // 打开`file`所指向的WAV文件并进行解析, 将其相关格式填写到spec中,
    // 并申请一段与音频数据总长度一致的内存, 将WAV文件中的音频数据读到申请的内存中,
    // 通过audio_buf返回内存的首地址, 并通过audio_len返回音频数据的字节数
    SDL_AudioSpec *SDL_LoadWAV(const char *file, SDL_AudioSpec *spec, uint8_t **audio_buf, uint32_t *audio_len);
    
    // 释放通过SDL_LoadWAV()申请的内存
    void SDL_FreeWAV(uint8_t *audio_buf);
    
    // 将缓冲区`src`中的`len`字节音频数据以`volume`的音量混合到另一个缓冲区`dst`中
    void SDL_MixAudio(uint8_t *dst, uint8_t *src, uint32_t len, int volume);
    

为了实现`SDL_LoadWAV()`, 你需要了解[WAV文件格式open in new window](http://soundfile.sapp.org/doc/WaveFormat/). "PCM和WAV的关系"与"BIN和ELF的关系"非常接近: 我们在PA2中直接播放PCM格式的音频数据, 而WAV文件可以看成是PCM音频数据和一些组织信息的组合, 解析WAV的过程就是在WAV的文件头部读出这些信息. 这个过程和你之前实现ELF loader是非常相似的. 此外, WAV文件也支持音频数据的压缩, 但在PA中使用的WAV文件都是非压缩的PCM格式, 因此你无需识别并处理压缩的情况.

最后来看看`SDL_MixAudio()`, 它用来对两段音频数据进行混合, 以达到同时播放它们的目的. 在混合之前, 还可以对其中一段音频数据的音量进行调整. 我们知道, 声音是若干正弦波的叠加, PCM编码就是对叠加后的曲线进行采样和量化得到的. 由于音量和曲线的振幅成正比, 因此调整音量就是按比例调整每一个采样点数据的值的大小. 我们在`navy-apps/libs/libminiSDL/include/sdl-audio.h`中定义了最大音量`SDL_MIX_MAXVOLUME`, 若`volume`参数为`SDL_MIX_MAXVOLUME`的1/4, 则表示将音频的音量调整为原来的1/4. 而要对两段音频进行混合, 就是将两者的曲线直接叠加. 不过叠加后还需要进行裁剪处理, 对于16位有符号数的格式来说, 叠加后的结果最大值为`32767`, 最小值为`-32768`, 这是为了防止叠加后的数据溢出导致音频的失真 (例如对于曲线上位于x轴上方的样本, 可能因溢出变成位于x轴下方). 理解这些内容之后, 就很容易实现`SDL_MixAudio()`了.

#### 运行带音效的Flappy Bird

实现上述API, 在Navy中运行带音效的Flappy Bird.

[#](#基础设施-3) 基础设施(3)
--------------------

如果你的仙剑奇侠传无法正确运行, 借助不同层次的native, 你应该可以很快定位到bug所在的层次. 如果是硬件bug, 你也许会陷入绝望之中: DiffTest速度太慢了, 尤其是基于QEMU的DiffTest! 有什么方法可以加快DiffTest的速度呢?

### [#](#自由开关difftest模式) 自由开关DiffTest模式

目前每次DiffTest都是从一开始进行, 但如果这个bug在很久之后才触发, 那么每次都从一开始进行DiffTest是没有必要的. 如果我们怀疑bug在某个函数中触发, 那么我们更希望DUT首先按照正常模式运行到这个函数, 然后开启DiffTest模式, 再进入这个函数. 这样, 我们就节省了前期大量的不必要的比对开销了.

为了实现这个功能, 关键是要在DUT运行中的某一时刻开始进入DiffTest模式. 而进入DiffTest模式的一个重要前提, 就是让DUT和REF的状态保持一致, 否则进行比对的结果就失去了意义. 我们又再次提到了状态的概念, 你应该再熟悉不过了: 计算机的状态就是计算机中的时序逻辑部件的状态. 这样, 我们只要在进入DiffTest模式之前, 把REF的寄存器和内存设置成和DUT一样, 它们就可以从一个相同的状态开始进行对比了.

为了控制DUT是否开启DiffTest模式, 我们还需要在简易调试器中添加如下两个命令:

*   `detach`命令用于退出DiffTest模式, 之后DUT执行的所有指令将不再与REF进行比对. 实现方式非常简单, 只需要让`difftest_step()`, `difftest_skip_dut()`和`difftest_skip_ref()`直接返回即可.
*   `attach`命令用于进入DiffTest模式, 之后DUT执行的所有指令将逐条与REF进行比对. 为此, 你还需要将DUT中物理内存的内容同步到REF相应的内存区间中, 并将DUT的寄存器状态也同步到REF中. 特别地, 如果你选择x86, 你需要绕过REF中`0x7c00`附近的内存区域, 这是因为REF在`0x7c00`附近会有GDT相关的代码, 覆盖这段代码会使得REF无法在保护模式下运行, 导致后续无法进行DiffTest. 事实上, 我们只需要同步`[0x100000, PMEM_SIZE)`的内存就足够了, 因为在NEMU中运行的程序不会使用`[0, 0x100000)`中的内存空间.

这样以后, 你就可以通过以下方式来在客户程序运行到某个目标位置的时候开启DiffTest了:

1.  去掉运行NEMU的`-b`参数, 使得我们可以在客户程序开始运行前键入命令
2.  键入`detach`命令, 退出DiffTest模式
3.  通过单步执行, 监视点, 断点等方式, 让客户程序通过正常模式运行到目标位置
4.  键入`attach`命令, 进入DiffTest模式, 注意设置REF的内存需要花费约数十秒的时间
5.  之后就可以在DiffTest模式下继续运行客户程序了

不过上面的方法还有漏网之鱼, 具体来说, 我们还需要处理一些特殊的寄存器, 因为它们也属于机器状态的一部分. 以x86为例, 我们还需要处理EFLAGS和IDTR这两个寄存器, 否则, 不一致的EFLAGS会导致接下来的`jcc`或者`setcc`指令在REF中的执行产生非预期结果, 而不一致的IDTR将会导致在REF中执行的系统调用因无法找到正确的目标位置而崩溃. 这里面的一个挑战是, REF中有的寄存器很难直接设置, 例如和QEMU通信的GDB协议中就没有定义IDTR的访问方式. 不过DiffTest提供的API已经可以解决这些问题了: 我们可以通过`difftest_memcpy_from_dut()`往REF中的空闲内存拷贝一段指令序列, 然后通过`difftest_setregs()`来让REF的pc指向这段指令序列, 接着通过`difftest_exec()`来让REF执行这段指令序列. 通过这种方式, 我们就可以让REF执行任意的程序了, 例如我们可以让REF来执行`lidt`指令, 这样就可以间接地设置IDTR了. 要设置EFLAGS寄存器, 可以通过执行`popf`指令来实现.

#### 实现可自由开关的DiffTest

根据上述内容, 在简易调试器中添加`detach`和`attach`命令, 实现正常模式和DiffTest模式的自由切换.

上述文字基本上把实现的思路介绍清楚了, 如果你遇到具体的问题, 就尝试自己分析解决吧.

### [#](#快照) 快照

更进一步的, 其实连NEMU也没有必要每次都从头开始执行. 我们可以像仙剑奇侠传的存档系统一样, 把NEMU的状态保存到文件中, 以后就可以直接从文件中恢复到这个状态继续执行了. 在虚拟化领域中, 这样的机制有一个专门的名字, 叫[快照open in new window](https://en.wikipedia.org/wiki/Virtualization#Snapshots). 如果你用虚拟机来做PA, 相信你对这个名词应该不会陌生. 在NEMU中实现快照是一件非常简单的事情, 我们只需要在简易调试器中添加如下命令即可:

*   `save [path]`, 将NEMU的当前状态保存到`path`指示的文件中
*   `load [path]`, 从`path`指示的文件中恢复NEMU的状态

#### 在NEMU中实现快照

关于NEMU的状态, 我们已经强调过无数次了, 快去实现吧. 另外, 由于我们可能会在不同的目录中执行NEMU, 因此使用快照的时候, 建议你通过绝对路径来指示快照文件.

[#](#展示你的批处理系统) 展示你的批处理系统
-------------------------

在PA3的最后, 你将会向Nanos-lite中添加一些简单的功能, 来展示你的批处理系统.

你之前已经在Navy上执行了开机菜单和NTerm, 但它们都不支持执行其它程序. 这是因为"执行其它程序"需要一个新的系统调用来支持, 这个系统调用就是`SYS_execve`, 它的作用是结束当前程序的运行, 并启动一个指定的程序. 这个系统调用比较特殊, 如果它执行成功, 就不会返回到当前程序中, 具体信息可以参考`man execve`. 为了实现这个系统调用, 你只需要在相应的系统调用处理函数中调用`naive_uload()`就可以了. 目前我们只需要关心`filename`即可, `argv`和`envp`这两个参数可以暂时忽略.

#### 可以运行其它程序的开机菜单

你需要实现`SYS_execve`系统调用, 然后通过开机菜单来运行其它程序. 你已经实现过很多系统调用了, 需要注意哪些细节, 这里就不啰嗦了.

#### 展示你的批处理系统

有了开机菜单程序之后, 就可以很容易地实现一个有点样子的批处理系统了. 你只需要修改`SYS_exit`的实现, 让它调用`SYS_execve`来再次运行`/bin/menu`, 而不是直接调用`halt()`来结束整个系统的运行. 这样以后, 在一个用户程序结束的时候, 操作系统就会自动再次运行开机菜单程序, 让用户选择一个新的程序来运行.

随着应用程序数量的增加, 使用开机菜单来运行程序就不是那么方便了: 你需要不断地往开机菜单中添加新的应用程序. 一种比较方便的做法是通过NTerm来运行这些程序, 你只要键入程序的路径, 例如`/bin/pal`.

#### 展示你的批处理系统(2)

在NTerm的內建Shell中实现命令解析, 把键入的命令作为参数调用`execve()`. 然后把NTerm作为Nanos-lite第一个启动的程序, 并修改`SYS_exit`的实现, 让它再次运行`/bin/nterm`. 目前我们暂不支持参数的传递, 你可以先忽略命令的参数.

键入命令的完整路径是一件相对繁琐的事情. 回想我们使用`ls`的时候, 并不需要键入`/bin/ls`. 这是因为系统中定义了`PATH`这个环境变量, 你可以通过`man execvp`来阅读相关的行为. 我们也可以让NTerm中的內建Shell支持这一功能, 你只需要通过`setenv()`函数来设置`PATH=/bin`, 然后调用`execvp()`来执行新程序即可. 调用`setenv()`时需要将`overwrite`参数设置为`0`, 这是为了可以在Navy native上实现同样的效果.

#### 为NTerm中的內建Shell添加环境变量的支持

这是一个非常简单的任务, 你只需要RTFM了解`setenv()`和`execvp()`的行为, 并对內建Shell的代码进行少量修改, 就可以得到一个和你平时的使用体验非常相似的Shell了.

#### 终极拷问

自古以来, 计算机系统方向的课程就有一个终极拷问:

> 当你在终端键入`./hello`运行Hello World程序的时候, 计算机究竟做了些什么?

你已经实现了批处理系统, 并且成功通过NTerm来运行其它程序. 尽管我们的批处理系统经过了诸多简化, 但还是保留了计算机发展史的精髓. 实现了批处理系统之后, 你对上述的终极拷问有什么新的认识?

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