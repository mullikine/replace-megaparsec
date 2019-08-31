-- |
-- Module    : Replace.Megaparsec
--
-- __Replace.Megaparsec__ is for finding text patterns, and also editing and
-- replacing the found patterns.
-- This activity is traditionally done with regular expressions,
-- but __Replace.Megaparsec__ uses "Text.Megaparsec" parsers instead for
-- the pattern matching.
--
-- __Replace.Megaparsec__ can be used in the same sort of “pattern capture”
-- or “find all” situations in which one would use Python
-- <https://docs.python.org/3/library/re.html#re.findall re.findall>,
-- or Perl
-- <https://perldoc.perl.org/functions/m.html m//>,
-- or Unix
-- <https://www.gnu.org/software/grep/ grep>.
--
-- __Replace.Megaparsec__ can be used in the same sort of “stream editing”
-- or “search-and-replace” situations in which one would use Python
-- <https://docs.python.org/3/library/re.html#re.sub re.sub>,
-- or Perl
-- <https://perldoc.perl.org/functions/s.html s///>,
-- or Unix
-- <https://www.gnu.org/software/sed/manual/html_node/The-_0022s_0022-Command.html sed>,
-- or
-- <https://www.gnu.org/software/gawk/manual/gawk.html awk>.
--
-- See the __replace-megaparsec__ package README for usage examples.

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Replace.Megaparsec
  (
    -- * Parser combinator
    sepCap
  , findAll
  , findAllCap

    -- * Running parser
  , streamEditT
  , streamEdit
  )
where


import Data.Void
import Data.Bifunctor
import Data.Functor.Identity
import Data.Proxy
import Data.Foldable
import Control.Exception (throw)
import Data.Typeable
import Control.Monad

import Text.Megaparsec

-- |
-- == Separate and capture
--
-- Parser combinator to find all of the non-overlapping ocurrences
-- of the pattern @sep@ in a text stream. Separate the stream into sections:
--
-- * sections which can parsed by the pattern @sep@ will be captured as
--   matching sections in 'Right'
-- * non-matching sections of the stream will be captured in 'Left'.
--
-- This parser will always consume its entire input and can never fail.
-- If there are no pattern matches, then the entire input stream will be
-- returned as a non-matching 'Left' section.
--
-- The pattern matching parser @sep@ will not be allowed to succeed without
-- consuming any input. If we allow the parser to match a zero-width pattern,
-- then it can match the same zero-width pattern again at the same position
-- on the next iteration, which would result in an infinite number of
-- overlapping pattern matches. So, for example, the
-- pattern @many digitChar@, which can match zero occurences of a digit,
-- will be treated by @sepCap@ as @some digitChar@, and required to match
-- at least one digit.
--
-- This @sepCap@ parser combinator is the basis for all of the other
-- features of this module. It is similar to the @sep*@ family of functions
-- found in
-- <http://hackage.haskell.org/package/parser-combinators/docs/Control-Monad-Combinators.html parser-combinators>
-- and
-- <http://hackage.haskell.org/package/parsers/docs/Text-Parser-Combinators.html parsers>
-- but, importantly, it returns the parsed result of the @sep@ parser instead
-- of throwing it away.
--
{-# INLINABLE sepCap #-}
sepCap
    :: forall e s m a. (MonadParsec e s m)
    => m a -- ^ The pattern matching parser @sep@
    -> m [Either (Tokens s) a]
sepCap sep = (fmap.fmap) (first $ tokensToChunk (Proxy::Proxy s))
             $ fmap sequenceLeft
             $ many $ fmap Right (try $ consumeSome sep) <|> fmap Left anySingle
  where
    sequenceLeft :: [Either l r] -> [Either [l] r]
    sequenceLeft = foldr consLeft []
      where
        consLeft :: Either l r -> [Either [l] r] -> [Either [l] r]
        consLeft (Left l) ((Left ls):xs) = (Left (l:ls)):xs
        consLeft (Left l) xs = (Left [l]):xs
        consLeft (Right r) xs = (Right r):xs
    -- If sep succeeds and consumes 0 input tokens, we must force it to fail,
    -- otherwise infinite loop
    consumeSome p = do
        offset1 <- getOffset
        x <- p
        offset2 <- getOffset
        when (offset1 >= offset2) empty
        return x

-- |
-- == Find all occurences, parse and capture pattern matches
--
-- Parser combinator for finding all occurences of a pattern in a stream.
--
-- Will call 'sepCap' with the 'Text.Megaparsec.match' combinator so that
-- the text which matched the pattern parser @sep@ will be returned in
-- the 'Right' sections, along with the result of the parse of @sep@.
--
-- @
--     findAllCap sep = 'sepCap' ('Text.Megaparsec.match' sep)
-- @
{-# INLINABLE findAllCap #-}
findAllCap
    :: MonadParsec e s m
    => m a -- ^ The pattern matching parser @sep@
    -> m [Either (Tokens s) (Tokens s, a)]
findAllCap sep = sepCap (match sep)

-- |
-- == Find all occurences
--
-- Parser combinator for finding all occurences of a pattern in a stream.
--
-- Will call 'sepCap' with the 'Text.Megaparsec.match' combinator and
-- return the text which matched the pattern parser @sep@ in
-- the 'Right' sections.
--
-- @
--     findAll sep = (fmap.fmap) ('Data.Bifunctor.second' fst) $ 'sepCap' ('Text.Megaparsec.match' sep)
-- @
{-# INLINABLE findAll #-}
findAll
    :: MonadParsec e s m
    => m a -- ^ The pattern matching parser @sep@
    -> m [Either (Tokens s) (Tokens s)]
findAll sep = (fmap.fmap) (second fst) $ sepCap (match sep)


-- |
-- == Stream editor
--
-- Also can be considered “find-and-replace”. Finds all
-- of the sections of the stream which match the pattern @sep@, and replaces
-- them with the result of the @editor@ function.
--
-- This function is not a “parser combinator,” it is
-- a “way to run a parser”, like 'Text.Megaparsec.parse'
-- or 'Text.Megaparsec.runParserT'.
--
-- === Access the matched section of text in the `editor`
--
-- If you want access to the matched string in the @editor@ function,
-- then combine the pattern parser @sep@ with 'Text.Megaparsec.match'.
-- This will effectively change the type of the `editor`
-- to `(s,a) -> m s`, and then we can write `editor` like:
--
-- @
--     let editor (matchString,parseResult) = return matchString
--
--     streamEditT ('Text.Megaparsec.match' sep) editor inputString
-- @
--
-- === Type constraints
--
-- The type of the stream of text that is input must
-- be @Stream s@ such that @Tokens s ~ s@, because we want
-- to output the same type of stream that was input. That requirement is
-- satisfied for all the 'Text.Megaparsec.Stream' instances included
-- with "Text.Megaparsec":
-- "Data.Text",
-- "Data.Text.Lazy",
-- "Data.Bytestring",
-- "Data.Bytestring.Lazy",
-- and "Data.String".
--
-- We need the @Monoid s@ instance so that we can @mappend@ the output
-- stream.
--
-- We need @Typeable s@ and @Show s@ for 'Control.Exception.throw'. In theory
-- this function should never throw an exception, because it only throws
-- when the 'sepCap' parser fails, and the 'sepCap' parser
-- can never fail. If this function ever throws, please report that as a bug.
--
-- === Underlying monad context
--
-- Both the parser @sep@ and the @editor@ function are run in the underlying
-- monad context.
--
-- If you want to do 'IO' operations in the @editor@ function or the
-- parser @sep@, then run this in 'IO'.
--
-- If you want the @editor@ function or the parser @sep@ to remember some state,
-- then run this in a stateful monad.
{-# INLINABLE streamEditT #-}
streamEditT
    :: forall s m a. (Stream s, Monad m, Monoid s, Tokens s ~ s, Show s, Show (Token s), Typeable s)
    => ParsecT Void s m a
        -- ^ The parser @sep@ for the pattern of interest.
    -> (a -> m s)
        -- ^ The @editor@ function. Takes a parsed result of @sep@
        -- and returns a new stream section for the replacement.
    -> s
        -- ^ The input stream of text to be edited.
    -> m s
streamEditT sep editor input = do
    runParserT (sepCap sep) "" input >>= \case
        (Left err) -> throw err -- sepCap can never fail, but if it does, throw
        (Right r) -> fmap fold $ traverse (either return editor) r



-- |
-- == Pure stream editor
--
-- Pure version of 'streamEditT'.
{-# INLINABLE streamEdit #-}
streamEdit
    :: forall s a. (Stream s, Monoid s, Tokens s ~ s, Show s, Show (Token s), Typeable s)
    => Parsec Void s a
        -- ^ The parser @sep@ for the pattern of interest.
    -> (a -> s)
        -- ^ The @editor@ function. Takes a parsed result of @sep@
        -- and returns a new stream section for the replacement.
    -> s
        -- ^ The input stream of text to be edited.
    -> s
streamEdit sep editor = runIdentity . streamEditT sep (Identity . editor)

