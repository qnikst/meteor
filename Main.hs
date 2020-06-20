module Main where

import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class
import Data.Function ((&), fix)
import Data.Text qualified as T
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import GHC.Generics
import Streaming.Prelude qualified as S
import Streaming.Prelude hiding (print, show)
import Streaming.Internal (Stream(..))
import Streaming
import System.Random.MWC

import Debug.Trace

-- | First we define our meteor type.
--
-- Pros over the reference implementation:
--   1. This type doesn't hardwire "region", region has nothing common
--     with the meteor and can't be the part of the type. It's just a leak
--     of an abstraction. Region is just an external label we set.
--
-- >>> show Meteor 1 2
-- Meteor 1.0 2.0
--
data Meteor = Meteor
  { size :: Double
  , mass :: Double
  }
  deriving stock (Eq, Ord, Show)
  deriving stock Generic

-- We set an interface
-- MonadIO m => Stream (Of m)

-- | This function can be build and provided by the external contributor,
-- or another team that can not care about your library, set of constrants
-- on the code, etc.
--
-- This function still follows DI approach and allows to define the part
-- of the funcitonality.
--
-- In this case random value generator and delay can be overriden. The function
-- keep only 'Monad m' constraint, it means that the function is actually pure one,
-- see discussion in step one.
--
-- Good points about this function comparing to the reference implementation:
--
--   1. This function is actually pure and can be run in Identity monad.
--      'randomSource (\(a,_) -> a) Nothing'
--
--   2. If logger is not passed it's checked only a single time and then randomly_delayed
--      if just eliminated and doesn't exist at all
-- 
--   3. Function is build atop of well known, well-tested, publically available
--      components on the contrary to the 'proprietary' framework with a single user
--      (be it an individual or the company).
--
-- Differences from the reference implementation. Logging in not implemented
-- because the logging is not a concern on this code, and can be easily implementd
-- by the caller of the 'randomSource' it was not 
--
-- Note. type '(forall a . Variate a => (a, a) -> m a)' is very polymorhicm you'll not be able
-- to write anything but return one of the input values or return a random one. 
--
randomSource
  :: (Monad m)
  => (forall a . Variate a => (a, a) -> m a) -- ^ Random generator
  -> (Maybe (m a))       -- ^ Possible delay
  -> Stream (Of Meteor) m a
randomSource random mdelay = random_source & randomly_delayed where
  random_source = repeatM $ do
    size <- random (1,100)
    mass <- random (size*1_000, size*10_000)
    pure Meteor{..}
  randomly_delayed = case mdelay of
    Nothing -> id
    Just delay -> fix $ \loop s ->
       lift (next s) >>= \case
         Left b -> pure b
         Right (a, rest) -> do
           yield a
           lift delay
           loop rest

---------------------------------------------------------------------------------------------
-- Application business logic.

-- | A helper to label the values based on the source.
--
-- Note. It goes to the company's stdlib
labeled :: Monad m
  => T.Text -> Stream (Of a) m ()
  -> Stream (Of (T.Text, a)) m ()
labeled l = S.map (l,)


-- | Create a communication channel, this one users bounded TQueue,
-- quite a fast communication primitive.
--
-- Queue itself is not exposed, so it's not possible to bypass the
-- implementation.
--
-- Note. It goes to the company's stdlib
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

data Config = Config
  { doLogDiscovered :: Bool
  , doLogTracked :: Bool
  , doLogTotal :: Bool
  , maxMeteors :: Maybe Int
  }

main :: IO ()
main = do
  (read, write) <- mkChannel
  withAsync (emit write) $ \_ -> do
    (storage :> total_) <- register read
    when doLogTotal $ putStrLn $ "Total " <> show (total_::Int)
    print storage
  where
    log_discovered :: Show a => Stream (Of a) IO b -> Stream (Of a) IO b
    log_discovered
        | doLogDiscovered
        = \s -> s & S.copy
                  & S.mapM_ (\meteor -> liftIO $ putStrLn $ "New meteor discovered: " <> show meteor)
        | otherwise = id
    emit write
      = forConcurrently ["north", "east", "west", "south"] $ \label -> do 
          g <- createSystemRandom
          randomSource (flip uniformR g)
            (Just $ uniformR (1_000_000, 2_000_000) g >>= threadDelay)
            & labeled label
            & log_discovered
            & write
    register read =
       read & (\s -> -- log all meteors that were tracked (if needed), check only a single time.
              if doLogTracked
              then 
                read & S.copy
                  & S.mapM_ (\meteor -> liftIO $ putStrLn $ "New meteor tracked: " <> show meteor)
              else s) 
            & maybe id S.take maxMeteors
            & S.store S.length_
            & S.fold (\x (l, m) -> Map.insertWith (<>) l (Set.singleton m) x) Map.empty id
    Config{..} = Config True True True (Just 10)
