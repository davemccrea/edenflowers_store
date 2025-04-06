defmodule EdenflowersWeb.Plugs.InitStore do
  import Plug.Conn

  require Ash.Query
  require Logger
  alias Edenflowers.Store.{Order, FulfillmentOption}

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :order_id) do
      # TODO: check order exists
      conn
    else
      case create_new_order() do
        {:ok, order} ->
          put_session(conn, :order_id, order.id)

        error ->
          raise "Failed to initialize store: #{inspect(error)}"
      end
    end
  end

  defp create_new_order do
    with {:ok, fulfillment_option} <- get_fulfillment_option(),
         {:ok, order} <- create_order(fulfillment_option.id) do
      {:ok, order}
    else
      error -> error
    end
  end

  defp get_fulfillment_option do
    FulfillmentOption
    |> Ash.Query.filter(fulfillment_method == :pickup)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :no_fulfillment_option}
      {:ok, option} -> {:ok, option}
      error -> error
    end
  end

  defp create_order(fulfillment_option_id) do
    Order
    |> Ash.Changeset.for_create(:create, %{fulfillment_option_id: fulfillment_option_id})
    |> Ash.create()
  end
end
