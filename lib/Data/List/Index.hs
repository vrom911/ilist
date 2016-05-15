{-# LANGUAGE
CPP,
MagicHash,
ScopedTypeVariables,
BangPatterns
  #-}


module Data.List.Index
(
  -- * Transformations
  imap,

  -- * Monadic functions
  imapM, iforM,
  imapM_, iforM_,
  itraverse, ifor,
  itraverse_, ifor_,

  -- * Special folds
  iall,
  iany,

  -- * Folds
  ifoldr,
  ifoldl, ifoldl',

  -- * Search
  ifilter,
  ifind,
  ifindIndex,
  ifindIndices,
)
where


#if __GLASGOW_HASKELL__ >= 710
import GHC.Base (oneShot)
#define ONE_SHOT oneShot
#else
#define ONE_SHOT
#endif

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
#endif

import Data.Maybe
import GHC.Exts

{- Left to do:

* a README with benchmarks (and lens comparisons)
* say that there's no documentation for functions because see their versions in Data.List
* write that the order for foldl is like this because it's like this in vector and containers
* link to similar things in vector and containers
* link from microlens to this
* link from my site to this

Functions
~~~~~~~~~

indexed
replaceAt/setAt
deleteAt
insertAt
modifyAt
alterF or something

iconcatMap
ifoldMap
ifoldrM
ifoldlM
imapAccumR
imapAccumL

ipartition

izipWith
izipWith3
izipWith4
izipWith5
izipWith6
izipWithM
izipWithM_
-}


imap :: (Int -> a -> b) -> [a] -> [b]
imap f xs = build $ \c n ->
  let go x cont i = f (I# i) x `c` cont (i +# 1#)
  in foldr go (\_ -> n) xs 0#
{-# INLINE imap #-}

iall :: (Int -> a -> Bool) -> [a] -> Bool
iall p ls = foldr go (\_ -> True) ls 0#
  where go x r k = p (I# k) x && r (k +# 1#)
{-# INLINE iall #-}

iany :: (Int -> a -> Bool) -> [a] -> Bool
iany p ls = foldr go (\_ -> False) ls 0#
  where go x r k = p (I# k) x || r (k +# 1#)
{-# INLINE iany #-}

imapM :: Monad m => (Int -> a -> m b) -> [a] -> m [b]
imapM f as = ifoldr k (return []) as
  where
    k i a r = do
      x <- f i a
      xs <- r
      return (x:xs)
{-# INLINE imapM #-}

iforM :: Monad m => [a] -> (Int -> a -> m b) -> m [b]
iforM = flip imapM
{-# INLINE iforM #-}

itraverse :: Applicative m => (Int -> a -> m b) -> [a] -> m [b]
itraverse f as = ifoldr k (pure []) as
  where
    k i a r = (:) <$> f i a <*> r
{-# INLINE itraverse #-}

ifor :: Applicative m => [a] -> (Int -> a -> m b) -> m [b]
ifor = flip itraverse
{-# INLINE ifor #-}

imapM_ :: Monad m => (Int -> a -> m b) -> [a] -> m ()
imapM_ f as = ifoldr k (return ()) as
  where
    k i a r = f i a >> r
{-# INLINE imapM_ #-}

iforM_ :: Monad m => [a] -> (Int -> a -> m b) -> m ()
iforM_ = flip imapM_
{-# INLINE iforM_ #-}

itraverse_ :: Applicative m => (Int -> a -> m b) -> [a] -> m ()
itraverse_ f as = ifoldr k (pure ()) as
  where
    k i a r = f i a *> r
{-# INLINE itraverse_ #-}

ifor_ :: Applicative m => [a] -> (Int -> a -> m b) -> m ()
ifor_ = flip itraverse_
{-# INLINE ifor_ #-}

-- Using unboxed ints here doesn't seem to result in any benefit
ifoldr :: (Int -> a -> b -> b) -> b -> [a] -> b
ifoldr f z xs = foldr (\x g i -> f i x (g (i+1))) (const z) xs 0
{-# INLINE ifoldr #-}

{-

ifoldr1 :: (Int -> a -> a -> a) -> [a] -> a
ifoldr1 f = go 0#
  where go _ [x]    = x
        go i (x:xs) = f (I# i) x (go (i +# 1#) xs)
        go _ []     = errorEmptyList "ifoldr1"
{-# INLINE [0] ifoldr1 #-}

-}

ifoldl :: forall a b. (b -> Int -> a -> b) -> b -> [a] -> b
ifoldl k z0 xs =
  foldr (\(v::a) (fn :: (Int, b) -> b) ->
          ONE_SHOT (\((!i)::Int, z::b) -> fn (i+1, k z i v)))
                   (snd :: (Int, b) -> b)
                   xs
                   (0, z0)
{-# INLINE ifoldl #-}

ifoldl' :: forall a b. (b -> Int -> a -> b) -> b -> [a] -> b
ifoldl' k z0 xs =
  foldr (\(v::a) (fn :: (Int, b) -> b) ->
          ONE_SHOT (\((!i)::Int, z::b) -> z `seq` fn (i+1, k z i v)))
                   (snd :: (Int, b) -> b)
                   xs
                   (0, z0)
{-# INLINE ifoldl' #-}

{-

ifoldl1 :: (a -> Int -> a -> a) -> [a] -> a
ifoldl1 f (x:xs) = ifoldl f x xs
ifoldl1 _ []     = errorEmptyList "ifoldl1"

ifoldl1' :: (a -> Int -> a -> a) -> [a] -> a
ifoldl1' f (x:xs) = ifoldl' f x xs
ifoldl1' _ []     = errorEmptyList "ifoldl1'"

-}

ifilter :: (Int -> a -> Bool) -> [a] -> [a]
ifilter p ls = build $ \c n ->
  let go x r k | p (I# k) x = x `c` r (k +# 1#)
               | otherwise  = r (k +# 1#)
  in foldr go (\_ -> n) ls 0#
{-# INLINE ifilter #-}

ifind :: (Int -> a -> Bool) -> [a] -> Maybe a
ifind p = listToMaybe . ifilter p

ifindIndex :: (Int -> a -> Bool) -> [a] -> Maybe Int
ifindIndex p = listToMaybe . ifindIndices p

ifindIndices :: (Int -> a -> Bool) -> [a] -> [Int]
ifindIndices p ls = build $ \c n ->
  let go x r k | p (I# k) x = I# k `c` r (k +# 1#)
               | otherwise  = r (k +# 1#)
  in foldr go (\_ -> n) ls 0#
{-# INLINE ifindIndices #-}

{-

errorEmptyList :: String -> a
errorEmptyList fun = error ("Data.List.Index." ++ fun ++ ": empty list")

-}
