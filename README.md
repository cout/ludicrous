The Ludicrous JIT Compiler
==========================

Ludicrous is a just-in-time compiler for Ruby 1.8 and 1.9.  Though still in the
experimental stage, its performance is roughly on par with YARV (better in some
benchmarks, though that may change as more features are added).  It's easy to
use:

    class MyClass
      ...
      include Ludicrous::Speed
      # (or Ludicrous::JITCompiled)
    end

How it works
------------

When you include the Ludicrous::JITCompiled module, stub methods are installed
for all the instance methods in that class.  When a stub method is called, the
method is compiled and the stub replaced with the compiled method.

To JIT-compile singleton methods, include the JITCompiled module in the
singleton class.

Installation
------------

To install:

    $ gem install ludicrous

You'll probably also need to install libjit for ruby-libjit to compile
correctly:

    $ wget ftp://ftp.gnu.org/gnu/dotgnu/libjit/libjit-0.1.2.tar.gz
    $ tar xvfz libjit-0.1.2.tar.gz
    $ cd libjit-0.1.2
    $ ./configure
    $ make
    $ sudo make install

and enjoy Ludicrous Speed:

    class Spaceball1
      ...
    end
    
    Spaceball1.go_plaid()

== Limitations

Ludicrous supports many features of Ruby, and passes all of the tests in bfts
as well as many of the tests that come with Ruby 1.8.6.  However, there are some
features that are unsupported, and will prove to be difficult to support.  These
include, but are not limited to:

* Trace funcs
* Using `break` with a value
* Accepting a block as an explicit parameter
* Certain methods: `eval`, `instance_eval`, `class_eval`, `module_eval`,
  `binding`
* `retry`
* Passing a proc as a block with the & operator 

Ludicrous will attempt to detect these cases and will throw an exception at
compile-time if it encounters any of them.  The stub method will then be
removed and replaced with the original method.

Ludicrous is also known to prevent thread switching in some cases.

It is currently impossible to trace functions that have been compiled with
Ludicrous.

Method arity is likely to change when a method is compiled with Ludicrous,
since arity is calculated differently for methods defined as C function
pointers.

Ludicrous currently makes assumptions that certain builtin methods will not be
redefined, such as arithmetic operators on Fixnum objects.  In the future,
Ludicrous will detect redefinition of these methods and fall back on slow
method calls if they are redefined (like YARV does now).

Ludicrous does not currently promote integers to bignums.

Match data (e.g. $~, $1..$9) modified in a jit-compiled function affects
match data in the callee.

Platforms
---------

Ludicrous has been developed and tested on Ubuntu Linux on a Pentium 3 with
Ruby 1.8.6.  It will likely work on any 32-bit platform where libjit has been
ported.  It is known to not work on 64-bit architectures.

License
-------

Ludicrous is licensed under the modified BSD license.  See the file COPYING
that was distributed with Ludicrous.

