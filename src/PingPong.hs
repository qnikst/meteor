{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE RankNTypes #-}
module PingPong where

import Control.Concurrent.STM
import Streaming.Prelude as S hiding (print)
import Streaming.Prelude qualified as S
import Streaming.Internal
import Control.Monad.IO.Class
import Control.Monad.Trans.Class
import Control.Monad.Trans.State
import Data.These
import Data.Function
import Text.Printf


data Ping = Ping deriving Show
data Pong = Pong deriving Show


mkChannel :: forall a m b . MonadIO m => IO (Stream (Of a) m (), Stream (Of a) m b -> m b)
mkChannel = do
  q <- liftIO $ newTBQueueIO 10 
  pure ( repeatM $ liftIO $ atomically $ readTBQueue q
       , fix $ \loop -> \case
          Return r -> pure r
          Effect m -> m >>= loop
          Step (a :> rest) -> do
            liftIO $ atomically $ writeTBQueue q a
            loop rest)
  
pingPong :: IO ()
pingPong = do
  (read_ping_pong, write_ping_pong) <- mkChannel
  yield (Left Ping) & write_ping_pong
  read_ping_pong
    & S.delay 0.3
    & S.maps S.eitherToSum
    & S.separate
    & S.mapM_ (\s -> liftIO $ do
        print s
        yield (Right Pong) & write_ping_pong)
    & S.mapM_ (\s -> liftIO $ do
        print s
        yield (Left Ping) & write_ping_pong)

feedBackPingPong :: IO ()
feedBackPingPong = evalStateT go (Left Ping) where
  go :: StateT (Either Ping Pong) IO ()
  go = init & S.delay 0.3
            & S.maps S.eitherToSum
            & S.separate
            & S.mapM_ (\s -> do
               liftIO $ print s
               lift $ put (Left s))
            & S.mapM_ (\s -> do
               liftIO $ print s
               put (Right s))
  init :: Stream (Of (Either Ping Pong)) (StateT (Either Ping Pong) IO) ()
  init = repeatM $ do
    get >>= \case
     Left Ping -> pure (Right Pong)
     Right Pong -> pure (Left Ping)
          
    


