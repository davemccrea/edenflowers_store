defmodule EdenflowersWeb.LiveToast do
  def new(key, msg, opts \\ []) do
    normalized_key = get_normalized_key(key)
    icon = get_icon(normalized_key)

    %{
      id: opts[:id] || Ecto.UUID.generate(),
      variant: normalized_key,
      icon: icon,
      message: msg,
      duration: opts[:duration] || "5000",
      closable: opts[:closable] || true,
      countdown: opts[:countdown] || nil
    }
  end

  defp get_normalized_key(key) when is_binary(key) do
    key = String.to_existing_atom(key)
    get_normalized_key(key)
  end

  defp get_normalized_key(key) when is_atom(key) do
    case key do
      :info -> :primary
      :error -> :danger
      :primary -> :primary
      :success -> :success
      :neutral -> :neutral
      :warning -> :warning
      :danger -> :danger
      _ -> :primary
    end
  end

  defp get_icon(key) do
    case key do
      :primary -> "info-circle"
      :success -> "check2-circle"
      :neutral -> "gear"
      :warning -> "exclamation-triangle"
      :danger -> "exclamation-octagon"
    end
  end
end
