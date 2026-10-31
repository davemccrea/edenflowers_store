defmodule Edenflowers.Marketing do
  @moduledoc """
  Entry point for the tracking tags Jennie puts on shop links she shares, so
  Umami can tell which post or newsletter brought a visitor and their order.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Marketing.TrackingTag do
      define :use_tracking_tag, action: :use, args: [:parameter, :value]
      define :use_tracking_tags, action: :use_all, args: [:tags]
      define :forget_tracking_tag, action: :forget, get_by: [:parameter, :value]
      define :recent_tracking_tags, action: :recent
      define :tracking_tag_suggestions, action: :suggestions
      define :tagged_url, args: [:url, :tags]
    end
  end
end
