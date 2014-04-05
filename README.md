Octopus
=======

Octopus is a hacking language. Dynamism and expressivity are the watchwords of Octopus; bonus points for parsimony of definition. These will continue to trump such trivial concerns as reliability or performance. For reliability, exercise taste and discretion; for performance, upgrade your hardware.

So why the name octopus? Octopuses are well known for their curiosity, intelligence, and dexterity, so it seems perfectly apt to associate such a dynamic like this after such a creature. Not to mention they are one of my favorite animals; I would probably keep one as a pet if it weren't so high-maintenance, or had less debatable ethics.

Installation
------------

There's a cabal package, so you can use `cabal install octopus`. Alternately, install from github with `git clone github.com/Zankoku-Okuno/octopus.git && cd octopus && cabal install`.

Usage
-----

Installation will give you the `octopus` program. So far, there are no fancy features, simply pass it a single file, and the file will be interpreted. If the file exports a binding for `main`, then its value will eval'd in the environment exported by the file.

There are a couple simple example programs under the `examples` directory. Import path normalization is not yet implemented, so interpret these files inside the directory.

Features
========

Executive summary: it's a Lisp with first-class-everything. For more detail, it has:

* Code is data/Data is code: Write programs to write your programs for you; eradicate boilerplate.
* Vau operator: You control when arguments get evaluated; mix and match lazy and strict.
* First-class environments: You decide what's in scope and what isn't.
* Immutable values: Data structures are default persistent; never corrupt your program state again.
* First-class control: Conquer the last resistance to abstraction; define any control flow construct ever dreamt of.
* Streamlined syntax: With only a handlful of grammar rules, you might miss them if you blink.
* Permissive identifiers: Unicode identifiers and user-defined disfixes open new possibilities; make Lisp read/write.
* Natural concurrency: Any concurrency model can be implemented as a library; tame the multiprocessing beast.

Future Features
---------------

These may be on the way, but Octopus is not a huge priority or anything, so we'll see. If I find myself not having fun implementing them, I'll probably just drop them.

* Channel-based concurrency.
* Deliver Octopus to the browser with an interpreter in Javascript.
* Foreign function interface to C code so you can jump out and leverage performance and existing libraries where needed.
* Formal definition.

Never-features
--------------

Good luck to the brave soul who wants to try a static analysis of Octopus, or any language with first-class environments.

That being said, static types are impossible in general, compilation gains you little. When faced with a choice between static and dynamic, Octopus will always choose dynamic, and that makes Octopus a horror story for compiler writers. That's fine, not every language need be compiled.

Status
======

* 2014-03-31: With bugfixes, achieved Turing-complete.
* 2014-04-03: Implemented an import. Well on the way to a useful language.

The Story
=========

Far be it from me to be dogmatic. I'm not usually a dynamic typing guy. I prefer the comfort of a type checker when I have to refactor a system of any size. I like knowing I already have 10x more wiggle room just from compiling to native code. But there comes a time in every programmer's life when they just want to mess around, to build something anxiety-free.

For me, Octopus is that that fun little romp. I started on a Thursday, and had the entire core language by the next Monday. Finishing up the basic primitives and providing an import mechanism is all there is left before it becomes a serious language. Well, and standard libraries... and a package manager... and a community,  but you get my point.

