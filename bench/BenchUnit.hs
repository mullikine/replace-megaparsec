{-# LANGUAGE OverloadedStrings #-}

import Text.Megaparsec
import Replace.Megaparsec
import Criterion.Main
import Criterion.Types
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Builder as BS.Builder
import qualified Data.Text as T
import Data.Foldable
import Data.Void

fooString :: String
-- fooString = fold $ replicate 10000 "       foo" -- a million bytes of foos
fooString = fold $ replicate 100 "       foo" -- a million bytes of foos

fooByteString :: BS.ByteString
fooByteString = BL.toStrict $ BS.Builder.toLazyByteString $ BS.Builder.string8 fooString

main :: IO ()
main = defaultMainWith (defaultConfig
            { reportFile = Just "criterion-report.html"
            , resamples = 100
            })
    [ bgroup "String"
        [ bench "sepCap" $ whnf
            (parseMaybe (sepCap (chunk "foo" :: Parsec Void String String)))
            fooString
        , bench "streamEdit" $ whnf
            (streamEdit (chunk "foo" :: Parsec Void String String) (const "bar"))
            fooString
        ]
    , bgroup "ByteString.Strict"
        [ bench "sepCap" $ whnf
            (parseMaybe (sepCap (chunk "foo" :: Parsec Void BS.ByteString BS.ByteString)))
            fooByteString
        , bench "streamEdit" $ whnf
            (streamEdit (chunk "foo" :: Parsec Void BS.ByteString BS.ByteString) (const "bar"))
            fooByteString
        ]
    ]

