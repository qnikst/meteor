-- | Example of building really small FRP-like example
module Step3 where

import Streaming.Prelude as S
import Control.Monad.Trans.Class
import Data.These
import Data.Function
import Text.Printf

run :: IO ()
run = S.iterate (+1) (0::Int)                                  -- Stream (Of Int)
  & delay 0.3                                                  -- timer
  & two_way (filtered even) (filtered odd)                     -- Stream (Of (These Int Int))
  & combine                                                    -- Stream (Of (Int, Int))
  & changes                                                    -- only changed values
  & S.mapM_ (\(x,y) -> printf "%i + %i = %i\n" x y (x+y))      -- combine
 
filtered :: Applicative m => (a -> Bool) -> a -> m (Maybe a)
filtered p a
  | p a = pure (Just a)
  | otherwise = pure Nothing

two_way
  :: Monad m
  => (a -> m (Maybe b))
  -> (a -> m (Maybe c))
  -> Stream (Of a) m r
  -> Stream (Of (These b c)) m r
two_way f g = fix $ \loop s ->
  lift (next s) >>= \case
    Left r -> pure r
    Right (x,rest) -> lift ((,) <$> f x <*> g x) >>= \case
      (Nothing, Nothing) -> loop rest
      (Just a, Nothing)  -> yield (This a) >> loop rest
      (Nothing, Just b)  -> yield (That b) >> loop rest
      (Just a, Just b)   -> yield (These a b) >> loop rest
  
changes :: (Eq a, Monad m) => Stream (Of a) m r -> Stream (Of a) m r
changes = init where
  init s = do
    lift (next s) >>= \case
      Left r -> pure r
      Right (x, rest) -> yield x >> go x rest
  go = fix $ \loop t s -> 
    lift (next s) >>= \case
      Left r -> pure r
      Right (x, rest) 
        | t == x -> go t rest
        | otherwise -> yield x >> go x rest

combine :: (Monad m) => Stream (Of (These a b)) m r -> Stream (Of (a,b)) m r
combine = init where
  init s = do
    lift (next s) >>= \case 
      Left r -> pure r
      Right (y, rest) -> check y rest
  check (These a b) s = yield (a, b) >> go (a,b) s
  check (This a) s = init1 (Left a) s
  check (That b) s = init1 (Right b) s
  init1 v s = lift (next s) >>= \case
    Left r -> pure r
    Right (y, rest) -> case (y,v) of
      (This a, Left _) -> init1 (Left a) rest
      (This a, Right b) -> check (These a b) rest
      (That b, Left a) -> check (These a b) rest
      (That b, Right _) -> init1 (Right b) rest
      (These{}, _)  -> check y rest
  go x@(a, b) s =
     lift (next s) >>= \case 
       Left r -> pure r
       Right (y, rest) -> case y of
         (This a') -> yield (a', b) >> go (a', b) rest
         (That b') -> yield (a, b') >> go (a, b') rest
         (These a' b') -> yield (a', b') >> go (a',b') rest

