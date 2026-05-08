defmodule EdenflowersWeb.LiveToast do
  def new(key, msg, opts \\ []) do
    normalized_key = get_normalized_key(key)

    %{
      id: opts[:id] || Ecto.UUID.generate(),
      variant: normalized_key,
      message: msg,
      duration: opts[:duration] || "5000",
      closable: opts[:closable] || true
    }
  end

  defp get_normalized_key(key) when is_binary(key) do
    key = String.to_existing_atom(key)
    get_normalized_key(key)
  end

  defp get_normalized_key(key) when is_atom(key) do
    case key do
      :info -> :info
      :error -> :error
      :primary -> :info
      :success -> :success
      :neutral -> :neutral
      :warning -> :warning
      :danger -> :error
      _ -> :info
    end
  end
end
