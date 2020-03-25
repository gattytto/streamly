{-# LANGUAGE BangPatterns              #-}
{-# LANGUAGE CPP                       #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Streamly.Internal.Data.Parser
-- Copyright   : (c) 2020 Composewell Technologies
-- License     : BSD3
-- Maintainer  : streamly@composewell.com
-- Stability   : experimental
-- Portability : GHC
--
-- Parsers.

module Streamly.Internal.Data.Parser
    (
      Parser (..)

    -- * Combinators
    , fromFold

    -- * Folds
    , any
    , all

    , sepBy
    , sepByMax
    , sepWithSuffix
    , wordBy

    -- * Parsers
    , takeWhile
    , takeEQ
    , takeGE

    , sepWithPrefix
    -- , sepWithInfix
    , groupBy
    )
where

import Prelude
       hiding (any, all, takeWhile)

import Streamly.Internal.Data.Parser.Types (Parser(..), Step(..))
import Streamly.Internal.Data.Fold.Types (Fold(..))

import Streamly.Internal.Data.Strict

-------------------------------------------------------------------------------
-- Upgrade folds to parses
-------------------------------------------------------------------------------
--
-- | The resulting parse never terminates and never errors out.
--
{-# INLINE fromFold #-}
fromFold :: Monad m => Fold m a b -> Parser m a b
fromFold (Fold fstep finitial fextract) = Parser step initial extract
    where

    initial = finitial
    step s a = Yield 0 <$> fstep s a
    extract s = do
        r <- fextract s
        return $ Right r

-------------------------------------------------------------------------------
-- Terminating folds
-------------------------------------------------------------------------------
--
-- |
-- >>> S.parse (PR.any (== 0)) $ S.fromList [1,0,1]
-- > Right True
--
{-# INLINABLE any #-}
any :: Monad m => (a -> Bool) -> Parser m a Bool
any predicate = Parser step initial (return . Right)
    where
    initial = return False
    step s a = return $
        if s
        then Stop 0 True
        else
            if predicate a
            then Stop 0 True
            else Yield 0 False

-- |
-- >>> S.parse (PR.all (== 0)) $ S.fromList [1,0,1]
-- > Right False
--
{-# INLINABLE all #-}
all :: Monad m => (a -> Bool) -> Parser m a Bool
all predicate = Parser step initial (return . Right)
    where
    initial = return True
    step s a = return $
        if s
        then
            if predicate a
            then Yield 0 True
            else Stop 0 False
        else Stop 0 False

-------------------------------------------------------------------------------
-- Taking elements
-------------------------------------------------------------------------------
--
-- | Stops after taking exactly @n@ input elements.
--
-- * Stops - after @n@ elements.
-- * Fails - if the stream ends before it can collect @n@ elements.
--
-- >>> S.parse (PR.takeExact 4 FL.toList) $ S.fromList [1,0,1]
-- > Left "takeEQ: Expecting exactly 4 elements, got 3"
--
-- /Internal/
--
{-# INLINABLE takeEQ #-}
takeEQ :: Monad m => Int -> Fold m a b -> Parser m a b
takeEQ n (Fold fstep finitial fextract) = Parser step initial extract

    where

    initial = (Tuple' 0) <$> finitial

    step (Tuple' i r) a = do
        res <- fstep r a
        let i1 = i + 1
            s1 = Tuple' i1 res
        return $ if i1 < n then Skip 0 s1 else Stop 0 s1

    extract (Tuple' i r) = fmap f (fextract r)

        where

        err =
               "takeEQ: Expecting exactly " ++ show n
            ++ " elements, got " ++ show i

        f x =
            if n == i
            then Right x
            else Left err

-- | Take at least @n@ input elements, but can collect more.
--
-- * Stops - never.
-- * Fails - if the stream end before producing @n@ elements.
--
-- >>> S.parse (PR.takeGE 4 FL.toList) $ S.fromList [1,0,1]
-- > Left "takeGE: Expecting at least 4 elements, got only 3"
--
-- >>> S.parse (PR.takeGE 4 FL.toList) $ S.fromList [1,0,1,0,1]
-- > Right [1,0,1,0,1]
--
-- /Internal/
--
{-# INLINABLE takeGE #-}
takeGE :: Monad m => Int -> Fold m a b -> Parser m a b
takeGE n (Fold fstep finitial fextract) = Parser step initial extract

    where

    initial = (Tuple' 0) <$> finitial

    step (Tuple' i r) a = do
        res <- fstep r a
        let i1 = i + 1
            s1 = Tuple' i1 res
        if i1 < n
        then return $ Skip 0 s1
        else return $ Yield 0 s1

    extract (Tuple' i r) = fmap f (fextract r)

        where

        err =
              "takeGE: Expecting at least " ++ show n
           ++ " elements, got only " ++ show i

        f x =
            if i >= n
            then Right x
            else Left err

-- | Take until the predicate fails. The element on which the predicate fails
-- is returned back to the input stream.
--
-- * Stops - when the predicate fails.
-- * Fails - never.
--
-- >>> S.parse (PR.takeWhile (== 0) FL.toList) $ S.fromList [0,0,1,0,1]
-- > Right [0,0]
--
-- @
-- breakOn p = takeWhile (not p)
-- @
--
-- /Internal/
--
{-# INLINABLE takeWhile #-}
takeWhile :: Monad m => (a -> Bool) -> Fold m a b -> Parser m a b
takeWhile predicate (Fold fstep finitial fextract) =
    Parser step initial extract

    where

    initial = finitial
    step s a = do
        if predicate a
        then Yield 0 <$> fstep s a
        else return $ Stop 1 s
    extract s = do
        b <- fextract s
        return $ Right b

-- | Keep taking elements until the predicate succeeds. Drop the succeeding
-- element.
--
-- * Stops - when the predicate succeeds.
-- * Fails - never.
--
-- >>> S.parse (PR.sepBy (== 1) FL.toList) $ S.fromList [0,0,1,0,1]
-- > Right [0,0]
--
-- >>> S.toList $ S.parseChunks (PR.sepBy (== 1) FL.toList) $ S.fromList [0,0,1,0,1]
-- > [[0,0],[0],[]]
--
-- S.splitOn pred f = S.parseChunks (PR.sepBy pred f)
--
-- /Internal/
--
{-# INLINABLE sepBy #-}
sepBy :: Monad m => (a -> Bool) -> Fold m a b -> Parser m a b
sepBy predicate (Fold fstep finitial fextract) =
    Parser step initial extract

    where

    initial = finitial
    step s a = do
        if not (predicate a)
        then Yield 0 <$> fstep s a
        else return $ Stop 0 s
    extract s = do
        b <- fextract s
        return $ Right b

-- | Keep taking elements until the predicate succeeds. Take the succeeding
-- element as well.
--
-- * Stops - when the predicate succeeds.
-- * Fails - never.
--
-- S.splitWithSuffix pred f = S.parseChunks (PR.sepWithSuffix pred f)
--
-- /Unimplemented/
--
{-# INLINABLE sepWithSuffix #-}
sepWithSuffix ::
    -- Monad m =>
    (a -> Bool) -> Fold m a b -> Parser m a b
sepWithSuffix = undefined

-- | Keep taking elements until the predicate succeeds. Return the succeeding
-- element back to the input.
--
-- * Stops - when the predicate succeeds.
-- * Fails - never.
--
-- S.splitWithPrefix pred f = S.parseChunks (PR.sepWithPrefix pred f)
--
-- /Unimplemented/
--
{-# INLINABLE sepWithPrefix #-}
sepWithPrefix ::
    -- Monad m =>
    (a -> Bool) -> Fold m a b -> Parser m a b
sepWithPrefix = undefined

-- | Split using a condition or a count whichever occurs first. This is a
-- hybrid of 'splitOn' and 'take'. The element on which the condition succeeds
-- is dropped.
--
-- /Internal/
--
{-# INLINABLE sepByMax #-}
sepByMax :: Monad m
    => (a -> Bool) -> Int -> Fold m a b -> Parser m a b
sepByMax predicate count (Fold fstep finitial fextract) =
    Parser step initial extract

    where

    initial = Tuple' 0 <$> finitial
    step (Tuple' i r) a = do
        res <- fstep r a
        let i1 = i + 1
            s1 = Tuple' i1 res
        if not (predicate a) && i1 < count
        then return $ Yield 0 s1
        else return $ Stop 0 s1
    extract (Tuple' _ r) = do
        b <- fextract r
        return $ Right b

-- | Like 'splitOn' after stripping leading, trailing, and repeated separators.
-- Therefore, @".a..b."@ with '.' as the separator would be parsed as
-- @["a","b"]@.  In other words, its like parsing words from whitespace
-- separated text.
--
-- * Stops - when it finds a word separator after a non-word element
-- * Fails - never.
--
-- S.wordsBy pred f = S.parseChunks (PR.wordBy pred f)
--
-- /Unimplemented/
--
{-# INLINABLE wordBy #-}
wordBy ::
    -- Monad m =>
    (a -> Bool) -> Fold m a b -> Parser m a b
wordBy = undefined

-- | @group cmp f $ S.fromList [a,b,c,...]@ assigns the element @a@ to the
-- first group, if @a \`cmp` b@ is 'True' then @b@ is also assigned to the same
-- group.  If @a \`cmp` c@ is 'True' then @c@ is also assigned to the same
-- group and so on. When the comparison fails a new group is started. Each
-- group is folded using the fold @f@ and the result of the fold is emitted in
-- the output stream.
--
-- * Stops - when the group ends.
-- * Fails - never.
--
-- S.groupsBy cmp f = S.parseChunks (PR.groupBy cmp f)
--
-- /Unimplemented/
--
{-# INLINABLE groupBy #-}
groupBy ::
    -- Monad m =>
    (a -> a -> Bool) -> Fold m a b -> Parser m a b
groupBy = undefined
