This is just an example proejct that shows how to build an
application based on the composable chunks. It's implemented
as a proper implementation of the show-case application [MeteorCounter](https://hackage.haskell.org/package/streaming).

While I was working with that application I has found that approach there
is too couples and barely maintainable. I'm not sure if going into details
will be appropriate here, maybe I'll do that in my blog some day.

This application was build as on a live-coding stream and it puts some
constraints on the code, because it was written interactively. The code
can be found in initial commit, and there is a video on [youtube
channel](https://youtu.be/ECO0GJPw8Bo) (in Russian).


After that code was restuctured for the better reading.

## Initial problem scope:

We want to build an application that gathers information about meteors
logs that information and dumps that inforamation to the logs.

We want to make in extensible and maintainable. The core of the maintainability
is an ability to setup a clean borders (and interfaces) between the components,
thus each component can evolve and be maintainable in isolation. As long as it
preseves the interface. 

The core requirements that we set:

  1. Each component should be as much isolated from the other as possible
  2. We should be able to build new components based on the previously implemented
     ones and the standard library
  3. It should be possible to extend and reuse the library in the other components.

## The plan.

As a main control-flow mechanism we will use Streams. Stream is an abstraction over
a sequence of monadic events. There are many implementations of streams but all of
them share similar functionality, the a way to process events in the bounded memory
with understandable resource control, and they are composable. In the other lanugages
the similar concept is coroutines.
We choose [streaming](https://hackage.haskell.org/package/streaming) package, but
we can choose any other implementation (pipes, conduits, machines, iteratee) anyway,
there are O(1) conversion/embedding functions between all those.

As a main communication control interface we will use [async](https://hackage.haskell.org/package/async). Async - in a wrapper
for the concurrent action that allows nice communication, checking control flow and
building process hierarchies. Async is de-facto standard implementation and unless
you have very valid reasons not to use it just use it and don't try to reimplement
that. A noticable example there is a nice version of async in `unliftio` package, for example unliftio
provides an mass execution functions that use bounded amount of worker threads, if
you already depend on that - you may chose unliftio version.

After fixing the tenchologies we want to use we setup a plan:

  1. Step0.hs — describes what is the stream and how it can be used for controlling
      the flow and for composition. It will not go into much details but will evolve
      in the future
      (70% Done)

  2. Step1.hs — describes how async can be used to create thread hierarchy and how
      we can use STM to build communication pipelines.
      (0% Done)

  3. Step2.hs — various notes on implemntation desing, how to make system composable
       do not hardwire parts on the implemnetation.
     (0% Done)

  4. Write a structured application (Main.hs)
     (0% Done)

  5. Add a foreword on applicability on the general approach and streams, show
     how to combine that with other approaches, show DI and test examples.


# Contributing

I'll gradly accept all contributions especially mistakes correction more explanations, 
examples, questions abou limitations.


