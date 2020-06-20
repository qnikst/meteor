-- | This module provides a very basic introduction into streams
-- abstraction and it's implementation in the streams library
module Step0 
  ( -- $introduction
    ex0
    -- $first-blood
  , ex1
  , ex2
  , ex3
  , ex4
  , gen
  ) where

import Control.Concurrent (threadDelay)
import Control.Monad.Trans.Resource
import Data.Aeson
import Data.ByteString.Streaming qualified as BS
import Data.ByteString.Streaming.Char8 qualified as BS8
import Data.Function ((&), fix)

import System.Random.MWC
import System.IO.Unsafe (unsafePerformIO) -- only for ghci needs

import Streaming.Prelude qualified as S
import Streaming.Prelude hiding (print)
import Streaming

-- $introduction
-- What is stream and when to use it?
--
-- Stream - is an abstraction over stream of monadic events, what does it ever mean?
--                 |                |          |
--                 +---------- it's an interfaces that hides an actual implementation
--                             behind a fixed interface
--                                  |          |
--                                  +------ we have an entity that provides a number
--                                          of events when "executed"
--                                             |
--                                             + each event may be associated with some
--                                               side effects and next action may depend
--                                               on the results of the previous one
--
-- Implementation:
-- 
-- Streams in the package are implemented as a structure:
--
-- data Stream :: f -> m -> r
--                |    |    |
--                |    |    +--- result of the computation
--                |    +-------- effects
--                +------------- event
--   
-- The library mostly works with f = (Of a)
--
-- data Of a b = !a :> b -- it's a spine-lazy infinite stream.
--
-- The main (internal) interface is function 'next':
--
-- next :: Monad m => Stream (Of a) m r -> m (Either  (a, Stream (Of a) m r))
--
-- This function tells if computation has finished or returns current value and
-- the next stream.
--
-- But the main benefit of the streams is that you can work with them like with
-- ordinary values and all combinators are ordinary functions that takes stream
-- and return the next one.
-- 
-- Let's write some examples. At first we want to learn how we can construct streams:

ex0 :: Monad m => Stream (Of Int) m ()
ex0 = yield 0

-- $first-blood
-- We have build a stream that emits a single value and return `()` when finished.
-- Let's see how that looks like. At first we will introduce a simple stream consumer
-- function `toList :: Monad m => Stream (Of a) m r -> m (Of [a] r)` it executes
-- all effects and build an entire list in the memory, so use it with caution.
--
-- We can run our stream as:
--
-- >>> ex0 & toList
-- [0] :> ()
--
--
--  |     |
--  |     +--- result
--  +--------- events we have gathered
--
-- here do is just an application with arguments flipped: 'x & f = f x'
-- 
-- We can compose streams so one is executed after the other using simple sequence:
--
-- >>> (ex0 >> ex0) & toList
-- [0,0] :> ()
--
--
-- You can see that the type of the stream mentions 'Monad m' it means that the stream
-- can be executed in any context or composed with any contest as long as it has 'Monad'
-- instance. It means that we can tell that this stream is pure (over Identity)
--
-- >>> :t ex0 @Identity
-- ex0 @Identity :: Stream (Of Int) Identity ()
--
-- So basically when you have a (Monad m) constraint in your stream it means that the
-- only thing it requires is ability to compose actions in order, it means that your
-- stream is actually a pure one.
--
-- Or we can compose it with more restricted streams for example with 
--   'S.print :: (MonadIO m, Show a) => Stream (Of a) m r -> m r'
-- that prints all values produced by the stream and thus works with any context as
-- long as it allows 'IO' actions.
--
-- >>> ex0 & S.print
-- 0
--
-- You can stream any ordinary Foldable value as a pure stream using function 'each'
ex1 :: Monad m => Stream (Of Int) m ()
ex1 = each [1,2,3,4]

-- There are many other construction functions, like
--   * repeat - build infinite stream of a single value
--   * iterate - build a stream based on the iterato
--   * unfoldr - generate a stream based on the carrier value
-- and so on
-- 
-- The main benefit of the streams is that you may have a large library of functions,
-- for example "Streaming.Prelude" module provides a set of functions that closely follows
-- "Prelude" module like 'S.take', 'S.repeat', 'S.zip' etc.
--
-- Now we will write a simple combinator that will add a constant label to all the
-- values we produce.

ex2 :: Monad m => String -> Stream (Of a) m () -> Stream (Of (String, a)) m ()

-- It looks like an ordinary map function it just works on the type of the stream
-- not on a result like fmap. And there is a function 'S.map' that does exactly that.

ex2 t = S.map ((t,))

-- >>> ex2 "foo" (each [1,2]) & toList
-- [("foo",1),("foo",2)] :> ()

-- Now let's enumerate all our values:
ex3 :: Monad m => Stream (Of a) m () -> Stream (Of (Int, a)) m ()
ex3 = S.zip (S.each [0..])

-- >>> ex3 (each ["a","b"]) & toList
-- [(0,"a"),(1,"b")] :> ()

-- Now, we will use one of the generator functions. Lets write some stream ex1,
-- that will generate an infinite list of random numbers:

ex4 :: GenIO -> Stream (Of Double) IO a
ex4 g = repeatM $ uniformR (-10, 10) g
--           |         |
--           |         +-- generate uniformly distributed random number
--           |
--           +-- repeat an effectrul (thus M is for) acition forever


-- | Dirty hack for GHCi.
gen :: GenIO
gen = unsafePerformIO createSystemRandom

-- We could run ex1, but if we consume that with toList it will take all memory and never
-- exists, so lets drop first 2 elements and take next 10.
--
-- @
-- > ex1 gen & S.drop 2 & S.take 10 & S.toList
-- [4.952577830917237,-1.6729214479195136,5.896127407925109,-0.8198262161852714,-1.1103258207104911,9.546641090307162e-2,-2.431771902873276,3.4927147099784666,9.35040064854693e-2,-6.655871087692383] :> ()
-- @


-- Next step is to write own combinator. We may generate random values, but we don't want
-- to flood the worker in our application so we want to introduce a delay. There is
-- a special 'S.delay' method that introduces constant delay between actions, but we will
-- introduce a random delay:
--

ex5 :: (MonadIO m) => GenIO -> Int -> Int -> Stream (Of a) m b -> Stream (Of a) m b
ex5 gen min_delay max_delay = fix $ \loop s -> do
   e -- get a next event from the stream
     <- 
      lift $ -- lift 'm' to the 'Stream _ m'
         next s
   case e of
     Left result -> pure result -- return a result
     Right (x, next) -> do
       yield x  -- emit next value
       liftIO $ -- lift 'IO' action into 'm'
         threadDelay =<< uniformR (min_delay, max_delay) gen
       loop next -- start working with the next stream

-- You can run @ex4 gen & ex5 gen 1000000 2000000 & S.print@ and see a result


-- The next topic is more complex. We want to read data from the jsonl file and interpret it.
-- jsonl is a format for the list of newline nedimited json objects.
-- Stream-framework provides an alternative to the lazy IO that has dominated the IO for the
-- vast majority of the GHC time.
--
-- streaming-bytestring introduces a new type for effectfuul ByteString. 'ByteString m a'
-- bytestring that can generate 'm' effects and that return 'a' as a result. In the library
-- there are many 'Stream ByteString m r' functions, and you can convet that to the stream
-- of usual strict bystrings by running toStrict, but lets go stepwise:

ex7 :: MonadResource m => FilePath -> Stream (Of Int) m ()
ex7 file = BS.readFile file -- BS.ByteString IO ()
  & BS8.lines -- Stream (ByteString IO) IO ()
              --            V
              -- Stream (Of ByteString) IO ()
  & mapped BS.toStrict 
  & S.map (eitherDecodeStrict @Int) -- Stream (Of Either String M) 
  & S.maps S.eitherToSum 
  & S.separate
  & S.mapM_ (\s -> liftIO . putStrLn $ "Huston, we have a problem: " <> s)


-- TODO: add a word on cloning streams and working with substreams
-- TODO: add a word on splitting the streams
-- TODO: add a word about composition and hoist
