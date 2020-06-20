
Lets take a look at the combinator that generates random values:

randomSource :: GenIO -> Stream (Of Meteor) IO a
randomSource g = repeatM $ do 
  x <- uniformR (-10, 10) g
  y <- uniformR (-10, 10) g
  pure Meteor{..}

The problem with this function is that it hardwires:

  1. usage of the random library
  2. 'IO' type of the underlyng context

Both may a good and a bad thing if you look at that. For example
it may be nice to allow consumer to choose the implementation
of the random values, this way the user may select one library
across entire application. On the other hand — if the library
require special properties of the random values, or uses API for
using distibutions, then not all the libraties will be acceptable
and it's completely OK to hardware concrete library that does work.

Same happens with IO, we alwas can list our stream from concete
IO to any MonadIO m context by writing 'hoist liftIO stream'.

So what if we want to give a user a way to control the effects,
we need a way to pass the function.

> randomSource :: (m a) -> Stream (Of a) IO ()
> randomSource f = repeatM f

Oops... It's just repeatM.. So actually we want to write

generate gen = do
  x <- uniformR (-10, 10) g
  y <- uniformR (-10, 10) g
  pure Meteor{..}

and call it as `repeatM (generate gen)`, but can we generalize 'generate',
yes we can we can instead of using 'uniformR' pass a funciton:

generate2 :: (forall . a -> a -> m a) -> m Meteor
generate2 f = do
  x <- f (-10) 10
  y <- f (-10) 10
  pure Meteor{..}

This way we can abstract over a concerete random library implementation
if neeed. And it may worth the case if you want to be able to easily switch
an implementation (Beware switch random library implementation is not an easy
task in a case if you really need specific properties of the random values, not
anything that is not very equal to each other).

As for testing if you have a pipeline that you want to test `random & pipeline`,
then during unit tests you can just replace `random` with another deterministic
stream and test your `pipeline`. And for real integration tests you want to
see random values anyway, so you have to keep random source.
