defmodule EdenflowersWeb.LiveToast do
  def new(variant, msg, opts \\ []) do
    %{
      id: opts[:id] || Ecto.UUID.generate(),
      variant: variant,
      message: msg,
      icon: icon_name(variant),
      duration: opts[:duration] || "Infinity",
      closable: opts[:closable] || false,
      countdown: opts[:countdown] || nil
    }
  end

  def icon_name(variant) do
    case variant do
      :primary -> "info-circle"
      :success -> "check2-circle"
      :neutral -> "gear"
      :warning -> "exclamation-triangle"
      :danger -> "exclamation-octagon"
    end
  end
end
