defmodule EdenflowersWeb.Admin.CustomerSearch do
  @moduledoc """
  The `customer_picker` on a form Jennie enters a sale in: what her search
  finds, and the customer's details filled in once she picks one.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Edenflowers.Accounts
  alias Edenflowers.Orders

  @doc """
  Offers the customers `term` finds, or the latest customers when it's empty,
  as the invoice page does, and says when a search finds none.
  """
  def search(socket, term) do
    term = String.trim(term)

    customers =
      Accounts.search_customers!(if(term == "", do: nil, else: term),
        actor: socket.assigns.current_user,
        query: [limit: 10]
      )

    options =
      Enum.map(customers, fn customer ->
        {Enum.join(Enum.reject([customer.name, to_string(customer.email)], &is_nil/1), " · "), customer.id}
      end)

    Phoenix.LiveView.send_update(LiveSelect.Component, id: "customer-select", options: options)

    socket
    |> assign(:customer_term, term)
    |> assign(:customer_search_empty?, term != "" && customers == [])
  end

  @doc "Opens the latest customers when Jennie clicks into the empty search, so a regular is a click away."
  def focus(%{assigns: %{customer_term: ""}} = socket), do: search(socket, "")
  def focus(socket), do: socket

  @doc """
  Fills in the name, email, phone and language of the customer just picked
  in `params`, unless `picked_id` is the one already picked.
  """
  def prefill(%{"customer_id" => id} = params, picked_id, actor) when id not in [nil, ""] and id != picked_id do
    case Accounts.get_customer_for_admin(id, actor: actor) do
      {:ok, customer} when not is_nil(customer) ->
        last = Orders.get_last_order_with_customer_phone!(customer.id, actor: actor, not_found_error?: false)

        Map.merge(params, %{
          "customer_name" => customer.name || "",
          "customer_email" => to_string(customer.email),
          "customer_phone_number" => if(last, do: last.customer_phone_number, else: ""),
          # Only a newsletter signup saves a customer's language, so most have
          # just the one their last order was placed in.
          "locale" => customer.locale || (last && last.locale) || params["locale"]
        })

      _ ->
        params
    end
  end

  def prefill(params, _picked_id, _actor), do: params
end
