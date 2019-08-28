import Text.Megaparsec
import Replace.Megaparsec

main = getContents >>= streamEditT (chunk "bash") (return . const "fnord") >>= putStr
