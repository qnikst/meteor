{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}
module Lib
  where

import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Concurrent (threadDelay)
import Control.Monad.Trans.Resource
import Data.Aeson
import Data.Int
import Data.Function ((&), fix)
import Data.ByteString.Streaming qualified as BS
import Data.ByteString.Streaming.Char8 qualified as BS8
import Data.Text qualified as T
import Control.Monad.IO.Class
import Control.Monad.Trans.Class
import Streaming.Prelude qualified as S
import Streaming.Prelude hiding (print)
import Streaming

import System.Random.MWC

import GHC.Generics
import System.IO.Unsafe

import Debug.Trace

-- -> print "hello"

test0 :: Monad m => Stream (Of Int) m ()
test0 = S.yield 1

-- & = flip ($) = \x f = f x

-- -> (test0 >> test0) & S.toList

-- (Double <*> Double)  ~~ Meteor

-- ToJSON
-- default toJSON :: Generic a => a -> Value
-- toJSON x = genericJSON (to x)

data Meteor = Meteor
  { x :: Double
  , y :: Double
  }
  deriving stock Show
  deriving stock Generic
  deriving anyclass (ToJSON, FromJSON)

newtype X0 = X0 Int deriving stock Show
-- -> X0 1

newtype X1 = X1 Int deriving newtype Show

-- -> X1 1

newtype X2 = X2 Int deriving anyclass ToJSON deriving stock Generic
newtype X3 = X3 Int deriving newtype ToJSON deriving stock Generic

-- $> (encode (X2 0), encode (X3 0))

newtype AsString a = AsString a

instance Show a => ToJSON (AsString a) where
  toJSON (AsString x) = toJSON (Prelude.show x)

newtype UserId = UserId Int64 
  deriving ToJSON via (AsString Int64)

  

-- $> encode (UserId 4)


-- instance Show X1 where show (X1 i) = show i

-- -$> (S.yield (Meteor 0 0) >> pure 1) & S.toList

-- each :: (Foldable f) => f a -> Stream (Of a) m ()

-- -> toList $ for (each [1..5]) $ \x -> for (each [1..5]) $ \y -> yield (Meteor x y)

gen :: GenIO
gen = unsafePerformIO createSystemRandom


randomSource :: GenIO -> Stream (Of Meteor) IO a
randomSource g = repeatM $ do 
  x <- uniformR (-10, 10) g
  y <- uniformR (-10, 10) g
  pure Meteor{..}

-- -> randomSource gen & S.take 10 & S.toList

delayed :: MonadIO m => Int -> Int
  -> Stream (Of a) m b -> Stream (Of a) m b
delayed min_delay max_delay = fix $ \loop s -> do
   e <- lift $ next s -- next :: Stream (Of a) m b 
                      --  m (Either b (a, Stream (Of a) m b)
   case e of
    Left b -> pure b
    Right (a, rest) -> do
      yield a
      delay <- liftIO $ uniformR (min_delay, max_delay) gen
      liftIO $ threadDelay delay
      loop rest

test :: MonadResource m => FilePath -> Stream (Of Meteor) m ()
test file = BS.readFile file -- BS.ByteString IO ()
  & BS8.lines -- Stream (ByteString IO) IO ()
              --            V
              -- Stream (Of ByteString) IO ()
  & mapped BS.toStrict 
  & S.map (eitherDecodeStrict @Meteor) -- Stream (Of Either String M) 
  & S.maps S.eitherToSum 
  & S.separate
  & S.mapM_ (\s -> liftIO . putStrLn $ "Huston, we have a problem: " <> s)
  

test1 = runResourceT @IO $ test "1.jsonl"
          & delayed 1_000_000 2_000_000
          & S.copy
          & S.print
          & S.filter (\Meteor{..} -> x > 3)
          & S.length_

labeled :: Monad m
  => T.Text -> Stream (Of a) m ()
  -> Stream (Of (T.Text, a)) m ()
labeled l = S.map (l,)


sourceQueue :: TBQueue a -> Stream (Of a) IO ()
sourceQueue q = fix $ \loop -> do
  x <- liftIO $ atomically $ readTBQueue q
  yield x
  loop

sinkQueue :: TBQueue a -> Stream (Of a) IO () -> IO ()
sinkQueue q = fix $ \loop s -> do
  next s >>= \case
    Left x -> pure x
    Right (x, rest) -> do
      liftIO $ atomically $ writeTBQueue q x
      loop rest


-- $> each [1,2,3] & id & S.toList 
--
-- IO 
--
--  do action1 ; action2
--      -------^
--
-- Monad m
-- Lang 
 
program = do 
  g1 <- createSystemRandom
  g2 <- createSystemRandom
  let sources = Prelude.zipWith
       (\l s -> s & labeled (T.pack (Prelude.show l)))
       [1..]
       [ randomSource g1 
           & delayed 5_000_00 2_000_000
       , randomSource g2
           & delayed 1_000_000 2_000_000
       ]
  q <- newTBQueueIO @ (T.Text, Meteor) 10 
  _ <- async $ forConcurrently_ sources (($) sinkQueue q)
  sourceQueue q & S.print
