{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE Trustworthy            #-}
{-# LANGUAGE UndecidableInstances   #-}
-- | Zipping and aligning of indexed functors.
module Data.Semialign.Indexed (
    SemialignWithIndex (..),
    -- * Diffing
    idiff, idiffNoEq
    ) where

import Prelude hiding (zip, zipWith)

import Control.Lens (FunctorWithIndex (imap))

import Data.Align
import Data.These
import Data.Witherable (Filterable (..))

-- Instances
import Control.Applicative   (ZipList)
import Data.Functor.Compose  (Compose (..))
import Data.Functor.Identity (Identity)
import Data.Functor.Product  (Product (..))
import Data.Hashable         (Hashable)
import Data.HashMap.Strict   (HashMap)
import Data.IntMap           (IntMap)
import Data.Map              (Map)
import Data.Sequence         (Seq)
import Data.Vector           (Vector)

import qualified Data.HashMap.Lazy as HM
import qualified Data.IntMap       as IntMap
import qualified Data.Map          as Map
import qualified Data.Vector       as V

-- $setup
-- >>> import Data.Map (fromList)

-- | Indexed version of 'Semialign'.
class (FunctorWithIndex i f, Semialign f) => SemialignWithIndex i f | f -> i where
    -- | Analogous to 'alignWith', but also provides an index.
    ialignWith :: (i -> These a b -> c) -> f a -> f b -> f c
    ialignWith f a b = imap f (align a b)

    -- | Analogous to 'zipWith', but also provides an index.
    izipWith :: (i -> a -> b -> c) -> f a -> f b -> f c
    izipWith f a b = imap (uncurry . f) (zip a b)

-------------------------------------------------------------------------------
-- base
-------------------------------------------------------------------------------

instance SemialignWithIndex () Maybe
instance SemialignWithIndex Int []
instance SemialignWithIndex Int ZipList

-------------------------------------------------------------------------------
-- transformers
-------------------------------------------------------------------------------

instance SemialignWithIndex () Identity

instance (SemialignWithIndex i f, SemialignWithIndex j g) => SemialignWithIndex (Either i j) (Product f g) where
    izipWith f (Pair fa ga) (Pair fb gb) = Pair fc gc where
        fc = izipWith (f . Left) fa fb
        gc = izipWith (f . Right) ga gb

    ialignWith f (Pair fa ga) (Pair fb gb) = Pair fc gc where
        fc = ialignWith (f . Left) fa fb
        gc = ialignWith (f . Right) ga gb

instance (SemialignWithIndex i f, SemialignWithIndex j g) => SemialignWithIndex (i, j) (Compose f g) where
    izipWith f (Compose fga) (Compose fgb) = Compose fgc where
        fgc = izipWith (\i -> izipWith (\j -> f (i, j))) fga fgb

    ialignWith f (Compose fga) (Compose fgb) = Compose $ ialignWith g fga fgb where
        g i (This ga)     = imap (\j -> f (i, j) . This) ga
        g i (That gb)     = imap (\j -> f (i, j) . That) gb
        g i (These ga gb) = ialignWith (\j -> f (i, j)) ga gb

-------------------------------------------------------------------------------
-- containers
-------------------------------------------------------------------------------

instance SemialignWithIndex Int Seq
instance SemialignWithIndex Int IntMap where
    izipWith = IntMap.intersectionWithKey
instance Ord k => SemialignWithIndex k (Map k) where
    izipWith = Map.intersectionWithKey

-------------------------------------------------------------------------------
-- unordered-containers
-------------------------------------------------------------------------------

instance (Eq k, Hashable k) => SemialignWithIndex k (HashMap k) where
    izipWith = HM.intersectionWithKey

-------------------------------------------------------------------------------
-- vector
-------------------------------------------------------------------------------

instance SemialignWithIndex Int Vector where
    izipWith = V.izipWith

-------------------------------------------------------------------------------
-- diffing
-------------------------------------------------------------------------------

-- | Diff two indexed structures:
--
-- >>> idiff [1, 2, 3, 4, 5] [1, 3, 3, 7]
-- [(1,Just 3),(3,Just 7),(4,Nothing)]
--
-- If your structure is explicitly indexed ('Map'-like), the result
-- type is awkward, and you may prefer 'Data.Semialign.diff' instead:
--
-- >>> idiff (fromList [(0, 1), (2, 3)]) (fromList [(0, 0), (1, 2)])
-- fromList [(0,(0,Just 0)),(1,(1,Just 2)),(2,(2,Nothing))]
idiff
  :: (SemialignWithIndex i f, Filterable f, Eq a)
  => f a -> f a -> f (i, Maybe a)
idiff = (catMaybes .) . ialignWith merge where
  merge i (This _) = Just (i, Nothing)
  merge i (That new) = Just (i, Just new)
  merge i (These old new)
    | old == new = Nothing
    | otherwise = Just (i, Just new)

-- | Diff two indexed structures without requiring an 'Eq'
-- instance. Instead, assume a new value wherever the structures
-- align:
--
-- >>> (fmap . fmap) ($ 3) (idiffNoEq [(+1)] [(*2), (const 0)] !! 1)
-- (1,Just 0)
idiffNoEq
  :: (SemialignWithIndex i f, Filterable f)
  => f a -> f a -> f (i, Maybe a)
idiffNoEq = (catMaybes .) . ialignWith merge where
  merge i (This _) = Just (i, Nothing)
  merge i (That new) = Just (i, Just new)
  merge i (These _ new) = Just (i, Just new)
