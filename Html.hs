-- Copyright 2015 Ruud van Asseldonk
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License version 3. See
-- the licence file in the root of the repository.

module Html ( Tag
            , TagProperties
            , applyTagsWhere
            , classifyTags
            , concatMapTagsWhere
            , filterTags
            , getTextInTag
            , isA
            , isAbbr
            , isCode
            , isEm
            , isH1
            , isH2
            , isHead
            , isHeader
            , isHeading
            , isMath
            , isOl
            , isPre
            , isScript
            , isSmcp
            , isSubtitle
            , isStrong
            , isStyle
            , isTeaser
            , isTeaserLink
            , isTitle
            , isUl
            , mapTagsWhere
            , mapText
            , mapTextWith
            , parseTags
            , renderTags
            ) where

-- This module contains utility functions for dealing with html.

import           Control.Monad (join, mplus, msum)
import           Data.List (intersperse)
import qualified Text.HTML.TagSoup as S

type Tag = S.Tag String

-- Tagsoup's default escape function escapes " to &quot;, but this is only
-- required inside quoted strings and only bloats the html in other places.
-- Even worse, it can render inline stylesheets invalid. I do not have
-- quoted strings with quotes in them, so it is fine not to escape quotes.
escapeHtml :: String -> String
escapeHtml = concatMap escape
  where escape '&' = "&amp;"
        escape '<' = "&lt;"
        escape '>' = "&gt;"
        escape  c  = [c]

-- Render options for Tagsoup that use the above escape function, and and that
-- do not escape inside <style> tags in addition to the default <script> tags.
renderOptions :: S.RenderOptions String
renderOptions = S.RenderOptions escapeHtml minimize rawTag
  where minimize _ = False -- Do not omit closing tags for empty tags.
        rawTag tag = (tag == "script") || (tag == "style")

-- Like Tagsoup's renderTags, but with the above options applied.
renderTags :: [Tag] -> String
renderTags = S.renderTagsOptions renderOptions

-- Reexport of Tagsoup's parseTags for symmetry.
parseTags :: String -> [Tag]
parseTags = S.parseTags

-- Applies a function to the text of a text tag.
mapText :: (String -> String) -> Tag -> Tag
mapText f (S.TagText str) = S.TagText (f str)
mapText _ tag             = tag

-- Various classifications for tags: inside body, inside code, etc.
data TagClass = A
              | Abbr
              | Code
              | Em
              | H1
              | H2
              | Head
              | Header
              | Math
              | Ol
              | Pre
              | Script
              | Smcp   -- Not an html tag, but a class.
              | Style
              | Strong
              | Teaser -- Not an html tag, but an id.
              | Ul
              deriving (Eq, Ord, Show)

tagClassFromName :: String -> Maybe TagClass
tagClassFromName name = case name of
  "a"      -> Just A
  "abbr"   -> Just Abbr
  "code"   -> Just Code
  "em"     -> Just Em
  "h1"     -> Just H1
  "h2"     -> Just H2
  "head"   -> Just Head
  "header" -> Just Header
  "math"   -> Just Math
  "ol"     -> Just Ol
  "pre"    -> Just Pre
  "script" -> Just Script
  "style"  -> Just Style
  "strong" -> Just Strong
  "ul"     -> Just Ul
  _        -> Nothing

tagClassFromAttributes :: [(String, String)] -> Maybe TagClass
tagClassFromAttributes = msum . fmap fromAttr
  where fromAttr attr = case attr of
          ("class", "smcp") -> Just Smcp
          ("id", "teaser")  -> Just Teaser
          _                 -> Nothing

-- Try to classify the tag based on the tag name, or based on the attributes
-- otherwise.
tagClass :: String -> [(String, String)] -> Maybe TagClass
tagClass name attrs = mplus (tagClassFromName name) (tagClassFromAttributes attrs)

-- A stack of tag name (string) and classification.
type TagStack = [(String, TagClass)]

updateTagStack :: TagStack -> Tag -> TagStack
updateTagStack ts tag = case tag of
  S.TagOpen name attrs -> case tagClass name attrs of
   Just classification -> (name, classification) : ts
   Nothing             -> ts
  S.TagClose name -> case ts of
    (topName, _) : more -> if topName == name then more else ts
    _                   -> ts
  _                     -> ts

-- Determines for every tag the nested tag classifications.
tagStacks :: [Tag] -> [[TagClass]]
tagStacks = fmap (fmap snd) . scanl updateTagStack []

data TagProperties = TagProperties { isA      :: Bool
                                   , isAbbr   :: Bool
                                   , isCode   :: Bool
                                   , isEm     :: Bool
                                   , isH1     :: Bool
                                   , isH2     :: Bool
                                   , isHead   :: Bool
                                   , isHeader :: Bool
                                   , isMath   :: Bool
                                   , isOl     :: Bool
                                   , isPre    :: Bool
                                   , isScript :: Bool
                                   , isSmcp   :: Bool
                                   , isStyle  :: Bool
                                   , isStrong :: Bool
                                   , isTeaser :: Bool
                                   , isUl     :: Bool }

isHeading :: TagProperties -> Bool
isHeading t = (isH1 t) || (isH2 t)

isTitle :: TagProperties -> Bool
isTitle t = (isHeader t) && (isH1 t)

isSubtitle :: TagProperties -> Bool
isSubtitle t = (isHeader t) && (isH2 t)

isTeaserLink :: TagProperties -> Bool
isTeaserLink t = (isTeaser t) && (isA t)

getProperties :: [TagClass] -> TagProperties
getProperties ts =
  let test cls = (cls `elem` ts)
  in TagProperties { isA      = test A
                   , isAbbr   = test Abbr
                   , isCode   = test Code
                   , isEm     = test Em
                   , isH1     = test H1
                   , isH2     = test H2
                   , isHead   = test Head
                   , isHeader = test Header
                   , isMath   = test Math
                   , isOl     = test Ol
                   , isPre    = test Pre
                   , isScript = test Script
                   , isSmcp   = test Smcp
                   , isStyle  = test Style
                   , isStrong = test Strong
                   , isTeaser = test Teaser
                   , isUl     = test Ul }

-- Given a list of tags, classifies them as "inside code", "inside em", etc.
classifyTags :: [Tag] -> [(Tag, TagProperties)]
classifyTags tags = zip tags $ fmap getProperties $ tagStacks tags

-- Discards tags for which the predicate returns false.
filterTags :: (TagProperties -> Bool) -> [Tag] -> [Tag]
filterTags predicate = fmap fst . filter (predicate . snd) . classifyTags

-- Applies a mapping function to the tags when the predicate p returns true for
-- that tag. The function tmap is a way to abstract over the mapping function,
-- it should not alter the length of the list.
applyTagsWhere :: (TagProperties -> Bool) -> ([Tag] -> [Tag]) -> [Tag] -> [Tag]
applyTagsWhere p tmap tags = fmap select $ zip (classifyTags tags) (tmap tags)
  where select ((orig, props), mapped) = if p props then mapped else orig

-- Applies the function f to all tags for which p returns true.
mapTagsWhere :: (TagProperties -> Bool) -> (Tag -> Tag) -> [Tag] -> [Tag]
mapTagsWhere p f = applyTagsWhere p (fmap f)

-- Applies the function f to all tags for which p returns true and flattens the result.
concatMapTagsWhere :: (TagProperties -> Bool) -> (Tag -> [Tag]) -> [Tag] -> [Tag]
concatMapTagsWhere p f = concatMap select . classifyTags
  where select (tag, props) = if (p props) then f tag else [tag]

-- Returns the the text in all tags that satisfy the selector.
getTextInTag :: (TagProperties -> Bool) -> String -> String
getTextInTag p  = join . intersperse " " . getText . (filterTags p) . parseTags
  where getText = fmap S.fromTagText . filter S.isTagText

-- Returns a list of text in text nodes, together with a value selected by f.
mapTextWith :: (TagProperties -> a) -> String -> [(String, a)]
mapTextWith f = fmap select . (filter $ S.isTagText . fst) . classifyTags . parseTags
  where select (tag, props) = (S.fromTagText tag, f props)
