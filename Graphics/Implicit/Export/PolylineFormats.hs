-- Implicit CAD. Copyright (C) 2011, Christopher Olah (chris@colah.ca)
-- Copyright (C) 2016, Julia Longtin (julial@turinglace.com)
-- Released under the GNU AGPLV3+, see LICENSE

-- Allow us to use explicit foralls when writing function type declarations.
{-# LANGUAGE ExplicitForAll #-}

{-# LANGUAGE OverloadedStrings #-}

module Graphics.Implicit.Export.PolylineFormats (svg, hacklabLaserGCode, dxf2) where

import Prelude((.), ($), (-), (+), (/), minimum, maximum, unzip, concat, show, (++), unwords, map, mapM_, snd, compare, min, max, length)

import Graphics.Implicit.Definitions (Polyline, ℝ, ℝ2)

import Graphics.Implicit.Export.TextBuilderUtils (Text, Builder, mempty, toLazyText, mconcat, bf, (<>), buildInt, buildTruncFloat)

import Text.Blaze.Svg.Renderer.Text (renderSvg)
import Text.Blaze.Svg11 ((!),docTypeSvg,g,polyline,toValue)
import Text.Blaze.Internal (stringValue)
import qualified Text.Blaze.Svg11.Attributes as A (version, width, height, viewbox, points, stroke, strokeWidth, fill)

import Data.List (sortBy)

svg :: [Polyline] -> Text
svg plines = renderSvg . svg11 . svg' $ plines
    where
      strokeWidth :: ℝ
      strokeWidth = 1.0
      (xmin, xmax, ymin, ymax) = (minimum xs - margin, maximum xs + margin, minimum ys - margin, maximum ys + margin)
           where margin = strokeWidth / 2
                 (xs,ys) = unzip (concat plines)

      svg11 = docTypeSvg ! A.version "1.1"
                         ! A.width  (stringValue $ show (xmax-xmin) ++ "mm")
                         ! A.height (stringValue $ show (ymax-ymin) ++ "mm")
                         ! A.viewbox (stringValue $ unwords . map show $ [0,0,xmax-xmin,ymax-ymin])

      -- The reason this isn't totally straightforwards is that svg has different coordinate system
      -- and we need to compute the requisite translation.
      svg' [] = mempty
      -- When we have a known point, we can compute said transformation:
      svg' polylines = thinBlueGroup $ mapM_ poly polylines

      poly line = polyline ! A.points pointList
          where pointList = toValue $ toLazyText $ mconcat [bf (x-xmin) <> "," <> bf (ymax - y) <> " " | (x,y) <- line]

      -- Instead of setting styles on every polyline, we wrap the lines in a group element and set the styles on it:
      thinBlueGroup = g ! A.stroke "rgb(0,0,255)" ! A.strokeWidth (stringValue $ show strokeWidth) ! A.fill "none" -- obj

-- DXF2 export in 2D. conforming to AutoCAD R12/13.
dxf2 :: [Polyline] -> Text
dxf2 plines = toLazyText $ dxf2Header <> dxf2Tables <> dxf2Blocks <> dxf2Entities
     where
      dxf2Header :: Builder
      dxf2Header = mconcat [
        "  0\n",   "SECTION\n",
        "  2\n",   "HEADER\n",
        "  9\n",   "$ACADVER\n",
        "  1\n",   "AC1009\n",
        "  9\n",   "$LIMMIN\n",
        " 10\n",   buildTruncFloat dxfxmin, "\n",
        " 20\n",   buildTruncFloat dxfymin, "\n",
        "  9\n",   "$LIMMAX\n",
        " 10\n",   buildTruncFloat dxfxmax, "\n",
        " 20\n",   buildTruncFloat dxfymax, "\n",
        "  9\n",   "$LUPREC\n",
        " 70\n",   "4\n",
        "  0\n",   "ENDSEC\n"
        ]
      dxf2Tables :: Builder
      dxf2Tables = mconcat [
        "  0\n",   "SECTION\n",
        "  2\n",   "TABLES\n",
        "  0\n",   "ENDSEC\n"
        ]
      dxf2Blocks :: Builder
      dxf2Blocks = mconcat [
        "  0\n",   "SECTION\n",
        "  2\n",   "BLOCKS\n",
        "  0\n",   "ENDSEC\n"
        ]
      dxf2Entities :: Builder
      dxf2Entities = mconcat [
        "  0\n",   "SECTION\n",
        "  2\n",   "ENTITIES\n",
        mconcat [ buildPolyline orderedPolyline | orderedPolyline <- (orderPolylines plines)], 
        "  0\n",   "ENDSEC\n"
        ]
      buildPolyline :: [ℝ2] -> Builder
      buildPolyline singlePolyline =
        mconcat [
        "  0\n",   "POLYLINE\n",
        "  8\n",   "0\n",
        "  6\n",   "CONTINUOUS\n",
        " 66\n",   "1\n",
        " 62\n",   buildInt $ length singlePolyline,"\n",
        " 10\n",   "0.0\n",
        " 20\n",   "0.0\n",
        " 30\n",   "0.0000\n",
        mconcat [ buildVertex vertex | vertex <- singlePolyline ],
        "  0\n",   "SEQEND\n"
        ]
      buildVertex :: (ℝ2) -> Builder
      buildVertex (x1,y1) =
        mconcat [
        "  0\n",  "VERTEX\n",
        "  8\n",  "0\n",
        "  10\n",   buildTruncFloat x1, "\n",
        "  20\n",   buildTruncFloat y1, "\n"
        ]
      (dxfxmin, dxfxmax, dxfymin, dxfymax) = (minimum xs, maximum xs, minimum ys, maximum ys)
      (xs, ys) = unzip (concat plines)

orderPolylines :: [Polyline] -> [Polyline]
orderPolylines plines =
  map snd . sortBy (\(a,_) (b, _) -> compare a b) . map (\x -> (polylineRadius x, x)) $ plines
  where
    polylineRadius :: [ℝ2] -> ℝ
    polylineRadius [] = 0
    polylineRadius polyline' = max (xmax' - xmin') (ymax' - ymin')
      where
        ((xmin', xmax'), (ymin', ymax')) = polylineRadius' polyline'
        polylineRadius' :: [ℝ2] -> (ℝ2, ℝ2)
        polylineRadius' [] = ((0,0),(0,0))
        polylineRadius' [(x,y)] = ((x,x),(y,y))
        polylineRadius' ((x,y):ps) = ((min x xmin,max x xmax),(min y ymin, max y ymax))
          where ((xmin, xmax), (ymin, ymax)) = polylineRadius' ps

-- Gcode generation for the laser cutter in HackLab. Complies with https://ws680.nist.gov/publication/get_pdf.cfm?pub_id=823374
hacklabLaserGCode :: [Polyline] -> Text
hacklabLaserGCode polylines = toLazyText $ gcodeHeader <> mconcat (map interpretPolyline (orderPolylines polylines)) <> gcodeFooter
    where
      gcodeHeader :: Builder
      gcodeHeader = mconcat [
                     "(generated by ImplicitCAD, based of hacklab wiki example)\n"
                    ,"M63 P0 (laser off)\n"
                    ,"G0 Z0.002 (laser off)\n"
                    ,"G21 (units=mm)\n"
                    ,"F400 (set feedrate)\n"
                    ,"M3 S1 (enable laser)\n\n"]
      gcodeFooter :: Builder
      gcodeFooter = mconcat [
                     "M5 (disable laser)\n"
                    ,"G00 X0.0 Y0.0 (move to 0)\n"
                    ,"M2 (end)"]
      gcodeXY :: ℝ2 -> Builder
      gcodeXY (x,y) = mconcat ["X", buildTruncFloat x, " Y", buildTruncFloat y]
      interpretPolyline (start:others) = mconcat [
                                          "G00 ", gcodeXY start
                                         ,"\nM62 P0 (laser on)\n"
                                         ,mconcat [ "G01 " <> gcodeXY point <> "\n" | point <- others]
                                         ,"M63 P0 (laser off)\n\n"
                                         ]
      interpretPolyline [] = mempty
