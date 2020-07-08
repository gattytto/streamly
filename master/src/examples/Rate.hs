import Streamly
import qualified Streamly.Prelude as S
import qualified Streamly.Internal.Prelude as Internal

main :: IO ()
main =
      S.mapM_ print
    $ asyncly
    $ avgRate 1
    $ Internal.timestamped
    $ S.repeatM (pure "tick")
