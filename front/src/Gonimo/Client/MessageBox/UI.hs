{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TupleSections #-}
module Gonimo.Client.MessageBox.UI where

import Reflex.Dom.Core
import Control.Lens
import Data.Monoid
import Data.Text (Text)
import Gonimo.Client.MessageBox.Internal
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Fix (MonadFix)
import qualified Gonimo.SocketAPI as API
import Gonimo.Client.Reflex.Dom
import Gonimo.SocketAPI.Types (InvitationReply(..))
import Gonimo.Server.Error (ServerError(..))

ui :: forall m t. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m, MonadIO (Performable m), PerformEvent t m)
      => Config t -> m (MessageBox t)
ui config = do
  actions <- fmap switchPromptlyDyn
    . widgetHold (pure never)
    . push (pure . id)
    $ displayMessages <$> config^.configMessage
  pure $ MessageBox actions

displayMessages  :: forall m t. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m, MonadIO (Performable m), PerformEvent t m)
      => [Message] -> Maybe (m (Event t [Action]))
displayMessages msgs = fmap mconcat <$> (sequence <$> traverse displayMessage msgs)


displayMessage :: forall m t. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m, MonadIO (Performable m), PerformEvent t m)
      => Message -> Maybe (m (Event t [Action]))
displayMessage msg = fmap (fmap (:[])) <$> case msg of
  ServerResponse res -> displayResponse res

displayResponse :: forall m t. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m, MonadIO (Performable m), PerformEvent t m)
      => API.ServerResponse -> Maybe (m (Event t Action))
displayResponse msg = case msg of
  API.ResError req err -> displayError req err
  API.ResAnsweredInvitation _ InvitationReject _ -> Just $
    box "Invitation rejected!" "panel-warning" $ do
      text "The invitation got rejected and is now invalid."
      (never,) <$> delayed 5
  API.ResAnsweredInvitation _ InvitationAccept _ -> Just $
    box "Invitation accepted!" "panel-success" $ do
      text "Your device is now a family member - make it a baby station!"
      (never,) <$> delayed 5
  _ -> Nothing

displayError :: forall m t. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m, MonadIO (Performable m), PerformEvent t m)
      => API.ServerRequest -> ServerError -> Maybe (m (Event t Action))
displayError req err = case (req, err) of
  (_, AlreadyFamilyMember fid) -> Just $
    box "Already a member of this family!" "panel-warning" $ do
      text "You are already a member of this family - wanna switch?"
      switch' <- buttonAttr ("class" =: "btn btn-block") $ text "Switch Family"
      (const (SelectFamily fid) <$> switch',) <$> delayed 10
  (_, NoSuchInvitation) -> Just $
    box "Invitation not found!" "panel-danger" $ do
      text "Invitations are only valid once!"
      elClass "span" "hidden-xs" $ text " (security and stuff, you know ...)"
      (never,) <$> delayed 6
  (_, InvitationAlreadyClaimed) -> Just $
    box "Invitation already claimed!" "panel-danger" $ do
      text "Some other device opened this invitation already!"
      elClass "span" "hidden-xs" $ text " (security and stuff, you know ...)"
      (never,) <$> delayed 6
  (_,_) -> Nothing

box :: forall m t a. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m)
      => Text -> Text -> m (Event t a, Event t ()) -> m (Event t a)
box title panelClass inner = mdo
  dynPair <- widgetHold (box' title panelClass inner) $ const (pure (never, never)) <$> closed
  let widgetEvent = switchPromptlyDyn . fmap fst $ dynPair
  let closed = switchPromptlyDyn . fmap snd $ dynPair
  pure widgetEvent

box' :: forall m t a. (DomBuilder t m, PostBuild t m, TriggerEvent t m, MonadIO m, MonadHold t m, MonadFix m, DomBuilderSpace m ~ GhcjsDomSpace, TriggerEvent t m)
      => Text -> Text -> m (Event t a, Event t ()) -> m (Event t a, Event t ())
box' title panelClass inner = do
  elClass "div" ("panel " <> panelClass) $ do
    closeClicked <- elClass "div" "panel-heading" $
      elAttr "div" ("style" =: "display: flex; justify-content: space-between;") $ do
        el "h1" $ text title
        closeButton
    (ev, closeEvent) <- elClass "div" "panel-body" inner
    pure (ev, leftmost [closeEvent, closeClicked])


closeButton :: DomBuilder t m => m (Event t ())
closeButton = do
  (e, _) <- elClass' "span" "close" $ text "x"
  return $ domEvent Click e
