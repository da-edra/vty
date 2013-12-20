{-# LANGUAGE NamedFieldPuns #-}
{-# OPTIONS_HADDOCK hide #-}
module Graphics.Vty.Image.Internal where

import Graphics.Vty.Attributes
import Graphics.Text.Width

import Control.DeepSeq

import qualified Data.Text.Lazy as TL

-- | A display text is a Data.Text.Lazy
--
-- TODO(corey): hm. there is an explicit equation for each type which goes to a lazy text. Each
-- application probably uses a single type. Perhaps parameterize the entire vty interface by the
-- input text type?
-- TODO: Try using a builder instead of a TL.Text instance directly. That might improve performance
-- for the usual case of appending a bunch of characters with the same attribute together.
type DisplayText = TL.Text

-- TODO: store a skip list in HorizText(?)
-- TODO: represent display strings containing chars that are not 1 column chars as a separate
-- display string value?
clip_text :: DisplayText -> Int -> Int -> DisplayText
clip_text txt left_skip right_clip =
    -- CPS would clarify this I think
    let (to_drop,pad_prefix) = clip_for_char_width left_skip txt 0
        txt' = if pad_prefix then TL.cons '…' (TL.drop (to_drop+1) txt) else TL.drop to_drop txt
        (to_take,pad_suffix) = clip_for_char_width right_clip txt' 0
        txt'' = TL.append (TL.take to_take txt') (if pad_suffix then TL.singleton '…' else TL.empty)
        clip_for_char_width 0 _ n = (n, False)
        clip_for_char_width w t n
            | TL.null t = (n, False)
            | w <  cw = (n, True)
            | w == cw = (n+1, False)
            | w >  cw = clip_for_char_width (w - cw) (TL.tail t) (n + 1)
            where cw = safe_wcwidth (TL.head t)
        clip_for_char_width _ _ _ = error "clip_for_char_width applied to undefined"
    in txt''

-- | This is the internal representation of Images. Use the constructors in "Graphics.Vty.Image" to
-- create instances.
--
-- Images are:
--
-- * a horizontal span of text
--
-- * a horizontal or vertical join of two images
--
-- * a two dimensional fill of the 'Picture's background character
--
-- * a cropped image
--
-- * an empty image of no size or content.
data Image = 
    -- | A horizontal text span is always >= 1 column and has a row height of 1.
      HorizText
      { attr :: Attr
      -- | The text to display. The display width of the text is always output_width.
      , display_text :: DisplayText
      -- | The number of display columns for the text. Always > 0.
      , output_width :: Int
      -- | the number of characters in the text. Always > 0.
      , char_width :: Int
      }
    -- | A horizontal join can be constructed between any two images. However a HorizJoin instance is
    -- required to be between two images of equal height. The horiz_join constructor adds background
    -- fills to the provided images that assure this is true for the HorizJoin value produced.
    | HorizJoin
      { part_left :: Image 
      , part_right :: Image
      , output_width :: Int -- ^ image_width part_left == image_width part_right. Always > 1
      , output_height :: Int -- ^ image_height part_left == image_height part_right. Always > 0
      }
    -- | A veritical join can be constructed between any two images. However a VertJoin instance is
    -- required to be between two images of equal width. The vert_join constructor adds background
    -- fills to the provides images that assure this is true for the VertJoin value produced.
    | VertJoin
      { part_top :: Image
      , part_bottom :: Image
      , output_width :: Int -- ^ image_width part_top == image_width part_bottom. always > 0
      , output_height :: Int -- ^ image_height part_top == image_height part_bottom. always > 1
      }
    -- | A background fill will be filled with the background char. The background char is
    -- defined as a property of the Picture this Image is used to form.
    | BGFill
      { output_width :: Int -- ^ always > 0
      , output_height :: Int -- ^ always > 0
      }
    -- | Crop an image horizontally to a size by reducing the size from the right.
    | CropRight
      { cropped_image :: Image
      -- | Always < image_width cropped_image > 0
      , output_width :: Int
      , output_height :: Int -- ^ image_height cropped_image
      }
    -- | Crop an image horizontally to a size by reducing the size from the left.
    | CropLeft
      { cropped_image :: Image
      -- | Always < image_width cropped_image > 0
      , left_skip :: Int
      -- | Always < image_width cropped_image > 0
      , output_width :: Int
      , output_height :: Int
      }
    -- | Crop an image vertically to a size by reducing the size from the bottom
    | CropBottom
      { cropped_image :: Image
      -- | image_width cropped_image
      , output_width :: Int
      -- | height image is cropped to. Always < image_height cropped_image > 0
      , output_height :: Int
      }
    -- | Crop an image vertically to a size by reducing the size from the top
    | CropTop
      { cropped_image :: Image
      -- | Always < image_height cropped_image > 0
      , top_skip :: Int
      -- | image_width cropped_image
      , output_width :: Int
      -- | Always < image_height cropped_image > 0
      , output_height :: Int
      }
    -- | The empty image
    --
    -- The combining operators identity constant. 
    -- EmptyImage <|> a = a
    -- EmptyImage <-> a = a
    -- 
    -- Any image of zero size equals the empty image.
    | EmptyImage
    deriving Eq

instance Show Image where
    show ( HorizText { attr, display_text, output_width, char_width } )
        = "HorizText " ++ show display_text
                       ++ "@(" ++ show attr ++ ","
                               ++ show output_width ++ ","
                               ++ show char_width ++ ")"
    show ( BGFill { output_width, output_height } )
        = "BGFill (" ++ show output_width ++ "," ++ show output_height ++ ")"
    show ( HorizJoin { part_left = l, part_right = r, output_width = c } )
        = "HorizJoin " ++ show c ++ " (" ++ show l ++ " <|> " ++ show r ++ ")"
    show ( VertJoin { part_top = t, part_bottom = b, output_width = c, output_height = r } )
        = "VertJoin [" ++ show c ++ ", " ++ show r ++ "] (" ++ show t ++ ") <-> (" ++ show b ++ ")"
    show ( CropRight { cropped_image, output_width, output_height } )
        = "CropRight [" ++ show output_width ++ "," ++ show output_height ++ "]"
                     ++ " (" ++ show cropped_image ++ ")"
    show ( CropLeft { cropped_image, left_skip, output_width, output_height } )
        = "CropLeft [" ++ show left_skip ++ "," ++ show output_width ++ "," ++ show output_height ++ "]"
                    ++ " (" ++ show cropped_image ++ ")"
    show ( CropBottom { cropped_image, output_width, output_height } )
        = "CropBottom [" ++ show output_width ++ "," ++ show output_height ++ "]"
                      ++ " (" ++ show cropped_image ++ ")"
    show ( CropTop { cropped_image, top_skip, output_width, output_height } )
        = "CropTop [" ++ show top_skip ++ "," ++ show output_width ++ "," ++ show output_height ++ "]"
                   ++ " (" ++ show cropped_image ++ ")"
    show ( EmptyImage ) = "EmptyImage"

-- | Attempts to pretty print just the structure of an image.
pp_image_structure :: Image -> String
pp_image_structure in_img = go 0 in_img
    where
        go indent img = tab indent ++ pp indent img
        tab indent = concat $ replicate indent "  "
        pp _ (HorizText {output_width}) = "HorizText(" ++ show output_width ++ ")"
        pp _ (BGFill {output_width, output_height})
            = "BGFill(" ++ show output_width ++ "," ++ show output_height ++ ")"
        pp i (HorizJoin {part_left = l, part_right = r, output_width = c})
            = "HorizJoin(" ++ show c ++ ")\n" ++ go (i+1) l ++ "\n" ++ go (i+1) r
        pp i (VertJoin {part_top = t, part_bottom = b, output_width = c, output_height = r})
            = "VertJoin(" ++ show c ++ ", " ++ show r ++ ")\n"
              ++ go (i+1) t ++ "\n"
              ++ go (i+1) b
        pp i (CropRight {cropped_image, output_width, output_height})
            = "CropRight(" ++ show output_width ++ "," ++ show output_height ++ ")\n"
              ++ go (i+1) cropped_image
        pp i (CropLeft {cropped_image, left_skip, output_width, output_height})
            = "CropLeft(" ++ show left_skip ++ "->" ++ show output_width ++ "," ++ show output_height ++ ")\n"
              ++ go (i+1) cropped_image
        pp i (CropBottom {cropped_image, output_width, output_height})
            = "CropBottom(" ++ show output_width ++ "," ++ show output_height ++ ")\n"
              ++ go (i+1) cropped_image
        pp i (CropTop {cropped_image, top_skip, output_width, output_height})
            = "CropTop("++ show output_width ++ "," ++ show top_skip ++ "->" ++ show output_height ++ ")\n"
              ++ go (i+1) cropped_image
        pp _ EmptyImage = "EmptyImage"
        
instance NFData Image where
    rnf EmptyImage = ()
    rnf (CropRight i w h) = i `deepseq` w `seq` h `seq` ()
    rnf (CropLeft i s w h) = i `deepseq` s `seq` w `seq` h `seq` ()
    rnf (CropBottom i w h) = i `deepseq` w `seq` h `seq` ()
    rnf (CropTop i s w h) = i `deepseq` s `seq` w `seq` h `seq` ()
    rnf (BGFill w h) = w `seq` h `seq` ()
    rnf (VertJoin t b w h) = t `deepseq` b `deepseq` w `seq` h `seq` ()
    rnf (HorizJoin l r w h) = l `deepseq` r `deepseq` w `seq` h `seq` ()
    rnf (HorizText a s w cw) = a `seq` s `deepseq` w `seq` cw `seq` ()

-- | The width of an Image. This is the number display columns the image will occupy.
image_width :: Image -> Int
image_width HorizText { output_width = w } = w
image_width HorizJoin { output_width = w } = w
image_width VertJoin { output_width = w } = w
image_width BGFill { output_width = w } = w
image_width CropRight { output_width  = w } = w
image_width CropLeft { output_width  = w } = w
image_width CropBottom { output_width = w } = w
image_width CropTop { output_width = w } = w
image_width EmptyImage = 0

-- | The height of an Image. This is the number of display rows the image will occupy.
image_height :: Image -> Int
image_height HorizText {} = 1
image_height HorizJoin { output_height = h } = h
image_height VertJoin { output_height = h } = h
image_height BGFill { output_height = h } = h
image_height CropRight { output_height  = h } = h
image_height CropLeft { output_height  = h } = h
image_height CropBottom { output_height = h } = h
image_height CropTop { output_height = h } = h
image_height EmptyImage = 0

