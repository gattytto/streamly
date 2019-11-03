{-# LANGUAGE FlexibleContexts #-}
-- |
-- Module      : Streamly.Data.Internal.Unicode.Stream
-- Copyright   : (c) 2018 Composewell Technologies
--
-- License     : BSD3
-- Maintainer  : streamly@composewell.com
-- Stability   : experimental
-- Portability : GHC
--
module Streamly.Internal.Data.Unicode.Stream
    (
    -- * Construction (Decoding)
      decodeChar8
    , decodeUtf8
    , decodeUtf8Lenient
    , D.DecodeError(..)
    , D.DecodeState
    , D.CodePoint
    , decodeUtf8Either
    , resumeDecodeUtf8Either
    , decodeUtf8Arrays
    , decodeUtf8ArraysLenient

    -- * Elimination (Encoding)
    , encodeChar8
    , encodeChar8Unchecked
    , encodeUtf8
{-
    -- * Unicode aware operations
    , toCaseFold
    , toLower
    , toUpper
    , toTitle

    -- * Operations on character strings
    , strip -- (dropAround isSpace)
    , stripEnd-}
    -- * Transformation
    , stripStart
    , foldLines
    , foldWords
    , unfoldLines
    , unfoldWords

    -- * Streams of Strings
    , lines
    , words
    , unlines
    , unwords
    )
where

import Control.Monad.IO.Class (MonadIO)
import Data.Char (ord)
import Data.Word (Word8)
import GHC.Base (unsafeChr)
import Streamly (IsStream, MonadAsync)
import Prelude hiding (String, lines, words, unlines, unwords)
import Streamly.Data.Fold (Fold)
import Streamly.Memory.Array (Array)
import Streamly.Internal.Data.Unfold (Unfold)

import qualified Streamly.Internal.Prelude as S
import qualified Streamly.Memory.Array as A
import qualified Streamly.Streams.StreamD as D

-- type String = List Char

-------------------------------------------------------------------------------
-- Encoding/Decoding Characters
-------------------------------------------------------------------------------

-- decodeWith :: TextEncoding -> t m Word8 -> t m Char
-- decodeWith = undefined

-------------------------------------------------------------------------------
-- Encoding/Decoding Unicode Characters
-------------------------------------------------------------------------------

-- | Decode a stream of bytes to Unicode characters by mapping each byte to a
-- corresponding Unicode 'Char' in 0-255 range.
{-# INLINE decodeChar8 #-}
decodeChar8 :: (IsStream t, Monad m) => t m Word8 -> t m Char
decodeChar8 = S.map (unsafeChr . fromIntegral)

-- | Encode a stream of Unicode characters to bytes by mapping each character
-- to a byte in 0-255 range. Throws an error if the input stream contains
-- characters beyond 255.
{-# INLINE encodeChar8 #-}
encodeChar8 :: (IsStream t, Monad m) => t m Char -> t m Word8
encodeChar8 = S.map convert
    where
    convert c =
        let codepoint = ord c
        in if codepoint > 255
           then error $ "Streamly.String.encodeChar8 invalid \
                    \input char codepoint " ++ show codepoint
           else fromIntegral codepoint

-- | Like 'encodeChar8' but silently truncates and maps input characters beyond
-- 255 to (incorrect) chars in 0-255 range. No error or exception is thrown
-- when such truncation occurs.
{-# INLINE encodeChar8Unchecked #-}
encodeChar8Unchecked :: (IsStream t, Monad m) => t m Char -> t m Word8
encodeChar8Unchecked = S.map (fromIntegral . ord)

-- | Decode a UTF-8 encoded bytestream to a stream of Unicode characters.
-- The incoming stream is truncated if an invalid codepoint is encountered.
{-# INLINE decodeUtf8 #-}
decodeUtf8 :: (Monad m, IsStream t) => t m Word8 -> t m Char
decodeUtf8 = D.fromStreamD . D.decodeUtf8 . D.toStreamD

{-# INLINE decodeUtf8Arrays #-}
decodeUtf8Arrays :: (MonadIO m, IsStream t) => t m (Array Word8) -> t m Char
decodeUtf8Arrays = D.fromStreamD . D.decodeUtf8Arrays . D.toStreamD

-- | Decode a UTF-8 encoded bytestream to a stream of Unicode characters.
-- Any invalid codepoint encountered is replaced with the unicode replacement
-- character.
{-# INLINE decodeUtf8Lenient #-}
decodeUtf8Lenient :: (Monad m, IsStream t) => t m Word8 -> t m Char
decodeUtf8Lenient = D.fromStreamD . D.decodeUtf8Lenient . D.toStreamD

{-# INLINE decodeUtf8Either #-}
decodeUtf8Either :: (Monad m, IsStream t)
    => t m Word8 -> t m (Either D.DecodeError Char)
decodeUtf8Either = D.fromStreamD . D.decodeUtf8Either . D.toStreamD

{-# INLINE resumeDecodeUtf8Either #-}
resumeDecodeUtf8Either
    :: (Monad m, IsStream t)
    => D.DecodeState
    -> D.CodePoint
    -> t m Word8
    -> t m (Either D.DecodeError Char)
resumeDecodeUtf8Either st cp =
    D.fromStreamD . D.resumeDecodeUtf8Either st cp . D.toStreamD

{-# INLINE decodeUtf8ArraysLenient #-}
decodeUtf8ArraysLenient ::
       (MonadIO m, IsStream t) => t m (Array Word8) -> t m Char
decodeUtf8ArraysLenient =
    D.fromStreamD . D.decodeUtf8ArraysLenient . D.toStreamD

-- | Encode a stream of Unicode characters to a UTF-8 encoded bytestream.
{-# INLINE encodeUtf8 #-}
encodeUtf8 :: (Monad m, IsStream t) => t m Char -> t m Word8
encodeUtf8 = D.fromStreamD . D.encodeUtf8 . D.toStreamD

{-
-------------------------------------------------------------------------------
-- Unicode aware operations on strings
-------------------------------------------------------------------------------

toCaseFold :: IsStream t => t m Char -> t m Char
toCaseFold = undefined

toLower :: IsStream t => t m Char -> t m Char
toLower = undefined

toUpper :: IsStream t => t m Char -> t m Char
toUpper = undefined

toTitle :: IsStream t => t m Char -> t m Char
toTitle = undefined

-------------------------------------------------------------------------------
-- Utility operations on strings
-------------------------------------------------------------------------------

strip :: IsStream t => t m Char -> t m Char
strip = undefined

stripEnd :: IsStream t => t m Char -> t m Char
stripEnd = undefined
-}

-- | Remove leading whitespace from a string.
--
-- > stripStart = S.dropWhile isSpace
{-# INLINE stripStart #-}
stripStart :: (Monad m, IsStream t) => t m Char -> t m Char
stripStart = S.dropWhile isSpace

-- | Fold each line of the stream using the supplied 'Fold'
-- and stream the result.
--
-- >>> S.toList $ foldLines FL.toList (S.fromList "lines\nthis\nstring\n\n\n")
-- ["lines", "this", "string", "", ""]
--
-- > foldLines = S.splitOnSuffix (== '\n')
--
{-# INLINE foldLines #-}
foldLines :: (Monad m, IsStream t) => Fold m Char b -> t m Char -> t m b
foldLines = S.splitOnSuffix (== '\n')

-- | Fold each word of the stream using the supplied 'Fold'
-- and stream the result.
--
-- >>>  S.toList $ foldWords FL.toList (S.fromList "fold these     words")
-- ["fold", "these", "words"]
--
-- > foldWords = S.wordsBy isSpace
--
{-# INLINE foldWords #-}
foldWords :: (Monad m, IsStream t) => Fold m Char b -> t m Char -> t m b
foldWords = S.wordsBy isSpace

foreign import ccall unsafe "u_iswspace"
  iswspace :: Int -> Int

-- | Code copied from base/Data.Char to INLINE it
{-# INLINE isSpace #-}
isSpace :: Char -> Bool
isSpace c
  | uc <= 0x377 = uc == 32 || uc - 0x9 <= 4 || uc == 0xa0
  | otherwise = iswspace (ord c) /= 0
  where
    uc = fromIntegral (ord c) :: Word

-- | Break a string up into a stream of strings at newline characters.
-- The resulting strings do not contain newlines.
--
-- > lines = foldLines A.write
--
-- >>> S.toList $ lines $ S.fromList "lines\nthis\nstring\n\n\n"
-- ["lines","this","string","",""]
--
-- If you're dealing with lines of massive length, consider using
-- 'foldLines' instead to avoid buffering the data in 'Array'.
{-# INLINE lines #-}
lines :: (MonadIO m, IsStream t) => t m Char -> t m (Array Char)
lines = foldLines A.write

-- | Break a string up into a stream of strings, which were delimited
-- by characters representing white space.
--
-- > words = foldWords A.write
--
-- >>> S.toList $ words $ S.fromList "A  newline\nis considered white space?"
-- ["A", "newline", "is", "considered", "white", "space?"]
--
-- If you're dealing with words of massive length, consider using
-- 'foldWords' instead to avoid buffering the data in 'Array'.
{-# INLINE words #-}
words :: (MonadIO m, IsStream t) => t m Char -> t m (Array Char)
words = foldWords A.write

-- | Unfold a stream to character streams using the supplied 'Unfold'
-- and concat the results suffixing a newline character @\\n@ to each stream.
--
{-# INLINE unfoldLines #-}
unfoldLines :: (MonadIO m, IsStream t) => Unfold m a Char -> t m a -> t m Char
unfoldLines = S.interposeSuffix '\n'

-- | Flattens the stream of @Array Char@, after appending a terminating
-- newline to each string.
--
-- 'unlines' is an inverse operation to 'lines'.
--
-- >>> S.toList $ unlines $ S.fromList ["lines", "this", "string"]
-- "lines\nthis\nstring\n"
--
-- > unlines = unfoldLines A.read
--
-- Note that, in general
--
-- > unlines . lines /= id
{-# INLINE unlines #-}
unlines :: (MonadIO m, IsStream t) => t m (Array Char) -> t m Char
unlines = unfoldLines A.read

-- | Unfold the elements of a stream to character streams using the supplied
-- 'Unfold' and concat the results with a whitespace character infixed between
-- the streams.
--
{-# INLINE unfoldWords #-}
unfoldWords :: (MonadIO m, IsStream t) => Unfold m a Char -> t m a -> t m Char
unfoldWords = S.interpose ' '

-- | Flattens the stream of @Array Char@, after appending a separating
-- space to each string.
--
-- 'unwords' is an inverse operation to 'words'.
--
-- >>> S.toList $ unwords $ S.fromList ["unwords", "this", "string"]
-- "unwords this string"
--
-- > unwords = unfoldWords A.read
--
-- Note that, in general
--
-- > unwords . words /= id
{-# INLINE unwords #-}
unwords :: (MonadAsync m, IsStream t) => t m (Array Char) -> t m Char
unwords = unfoldWords A.read