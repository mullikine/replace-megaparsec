-- |
-- Module    : Replace.Megaparsec.Internal.Text
-- Copyright : ©2019 James Brock
-- License   : BSD2
-- Maintainer: James Brock <jamesbrock@gmail.com>
--
-- This internal module is for 'Data.Text.Text' specializations.
--
-- The functions in this module are supposed to be chosen automatically
-- by rewrite rules in the "Replace.Megaparsec" module, so you should never
-- need to import this module.

{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}

module Replace.Megaparsec.Internal.Text
  (
    -- * Parser combinator
    sepCapText
  )
where

import Control.Monad
import qualified Data.Text as T
import Data.Text.Internal (Text(..))
import Text.Megaparsec

{-# INLINE [1] sepCapText #-}
sepCapText
    :: forall e s m a. (MonadParsec e s m, s ~ T.Text)
    => m a -- ^ The pattern matching parser @sep@
    -> m [Either (Tokens s) a]
sepCapText sep = getInput >>= go
  where
    -- the go function will search for the first pattern match,
    -- and then capture the pattern match along with the preceding
    -- unmatched string, and then recurse.
    -- restBegin is the rest of the buffer after the last pattern
    -- match.
    go restBegin@(Text tarray beginIndx beginLen) = do
        (<|>)
            ( do
                (Text _ _ thisLen) <- getInput
                -- About 'thisiter':
                -- It looks stupid and introduces a completely unnecessary
                -- Maybe, but when I refactor to eliminate 'thisiter' and
                -- the Maybe then the benchmarks get dramatically worse.
                thisiter <- (<|>)
                    ( do
                        x <- sep
                        restAfter@(Text _ _ afterLen) <- getInput
                        -- Don't allow a match of a zero-width pattern
                        when (afterLen >= thisLen) empty
                        pure $ Just (x, restAfter)
                    )
                    (anySingle >> pure Nothing)
                case thisiter of
                    (Just (x, restAfter)) | thisLen < beginLen -> do
                        -- we've got a match with some preceding unmatched string
                        let unmatched = Text tarray beginIndx (beginLen - thisLen)
                        (Left unmatched:) <$> (Right x:) <$> go restAfter
                    (Just (x, restAfter)) -> do
                        -- we're got a match with no preceding unmatched string
                        (Right x:) <$> go restAfter
                    Nothing -> go restBegin -- no match, try again
            )
            ( do
                    -- We're at the end of the input, so return
                    -- whatever unmatched string we've got since offsetBegin
                if beginLen > 0 then
                    pure [Left restBegin]
                else pure []
            )

