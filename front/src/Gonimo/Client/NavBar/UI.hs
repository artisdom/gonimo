module Gonimo.Client.NavBar.UI where

import Control.Lens
import Reflex.Dom
import Gonimo.Client.NavBar.Internal
import Gonimo.Client.Reflex.Dom
import qualified Gonimo.Client.Family.Internal as Family
import qualified Gonimo.Client.App.Types as App


navBar :: forall m t. (HasWebView m, MonadWidget t m)
      => Config t -> m (NavBar t)
navBar config = do
  elClass "div" "navbar navbar-default" $ do
    elClass "div" "container" $ do
      backClicked' <- buttonAttr ("class" =: "btn btn-default navbar-btn") $
                      elClass "span" "glyphicon glyphicon-menu-left" blank
      homeClicked' <- buttonAttr ("class" =: "btn btn-default navbar-btn") $
                      elClass "span" "glyphicon glyphicon-home" blank
      elClass "div" "nav navbar-nav navbar-right" $ do
        elClass "p" "" $
          dynText $ config^.configDeviceName
        elClass "p" "" $ do
          let cFamilyName = Family.currentFamilyName
                            $ Family.DefiniteFamily
                            (config^.configLoaded^.App.families)
                            (config^.configLoaded^.App.selectedFamily)
          dynText cFamilyName
      pure $ NavBar backClicked' homeClicked'
  -- where
    -- navLogo
    --   = elAttr "img" ( "alt" =: "gonimo"
    --                  <> "src" =: "pix/gonimo-brand-01.svg"
    --                  <> "height" =: "50px"
    --                  <> "style" =: "padding: 2px 3.5px 0px 3.5px;"
    --                  ) blank