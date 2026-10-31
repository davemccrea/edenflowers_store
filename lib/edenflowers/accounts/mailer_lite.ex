defmodule Edenflowers.Accounts.MailerLite do
  @moduledoc """
  The MailerLite API calls behind the newsletter. The site owns consent and
  the Newsletter group: its active members are the newsletter list, and
  campaigns go to that group. MailerLite owns unsubscribes, which are
  account-wide. Other groups and contacts are Jennie's and the site leaves
  them alone.

  Each subscriber carries name, last_name and phone (E.164, from their latest
  order) plus the custom fields language (en-GB, sv-FI or fi), order_count,
  last_order_date and total_spent. The custom fields have to exist in
  MailerLite: language as text, order_count and total_spent as number,
  last_order_date as date.

  Does nothing while no API key is configured.
  """

  alias Edenflowers.PhoneNumber

  @page_size 1000
  @newsletter_group_id "202876690108515964"

  def configured?, do: Application.get_env(:edenflowers, :mailerlite_api_key) != nil

  @doc """
  Makes a user who opted in on the site an active subscriber, lifting an
  older unsubscribe. Only for a fresh opt-in: the site's opt-in is newer
  than anything MailerLite holds.
  """
  def subscribe(user) do
    upsert(%{
      email: normalize(user.email),
      fields: fields(user),
      groups: [@newsletter_group_id],
      status: "active",
      resubscribe: true
    })
  end

  @doc """
  Refreshes a subscriber's fields and puts them in the Newsletter group
  without touching their status, so an unsubscribe, bounce or spam complaint
  in MailerLite stands. Creates them as active if MailerLite doesn't have
  them yet.
  """
  def update_fields(user) do
    upsert(%{email: normalize(user.email), fields: fields(user), groups: [@newsletter_group_id]})
  end

  def unsubscribe(email), do: upsert(%{email: normalize(email), status: "unsubscribed"})

  @doc "Lowercased addresses of every subscriber in the account with the given status."
  def list(status) do
    with {:ok, subscribers} <- list("/subscribers", status, nil, []) do
      {:ok, Enum.map(subscribers, &normalize(&1["email"]))}
    end
  end

  @doc "Active members of the Newsletter group, as lowercased address => subscriber id."
  def newsletter_members do
    with {:ok, subscribers} <- list("/groups/#{@newsletter_group_id}/subscribers", "active", nil, []) do
      {:ok, Map.new(subscribers, &{normalize(&1["email"]), &1["id"]})}
    end
  end

  @doc "Takes a subscriber out of the Newsletter group, leaving their status and other groups as they are."
  def remove_from_newsletter(subscriber_id) do
    case Req.delete(client(), url: "/subscribers/#{subscriber_id}/groups/#{@newsletter_group_id}") do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      other -> error(other)
    end
  end

  defp list(url, status, cursor, acc) do
    params = Enum.reject([{"filter[status]", status}, limit: @page_size, cursor: cursor], &is_nil(elem(&1, 1)))

    case Req.get(client(), url: url, params: params) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data, "meta" => meta}}} ->
        acc = acc ++ data

        case meta["next_cursor"] do
          nil -> {:ok, acc}
          next -> list(url, status, next, acc)
        end

      other ->
        error(other)
    end
  end

  defp upsert(body) do
    case Req.post(client(), url: "/subscribers", json: body) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      other -> error(other)
    end
  end

  defp fields(user) do
    %{
      name: user.first_name,
      last_name: user.last_name,
      phone: e164(user.phone_number),
      language: user.locale,
      order_count: user.placed_order_count,
      last_order_date: user.last_ordered_at && Date.to_iso8601(DateTime.to_date(user.last_ordered_at)),
      total_spent: Decimal.to_float(user.total_spent)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp e164(phone_number) do
    case PhoneNumber.format(phone_number, :e164) do
      {:ok, formatted} -> formatted
      :error -> nil
    end
  end

  defp error({:ok, %Req.Response{status: status, body: body}}), do: {:error, {:mailerlite_http_error, status, body}}
  defp error({:error, reason}), do: {:error, {:mailerlite_request_failed, reason}}

  # MailerLite stores addresses lowercased; the app keeps the case the customer typed.
  defp normalize(email), do: email |> to_string() |> String.downcase()

  # :transient also retries the POSTs when MailerLite's 120 requests a minute
  # are used up, waiting as long as its Retry-After says.
  defp client do
    Req.new(
      base_url: "https://connect.mailerlite.com/api",
      auth: {:bearer, Application.fetch_env!(:edenflowers, :mailerlite_api_key)},
      headers: [accept: "application/json"],
      retry: :transient
    )
    |> Req.merge(Application.get_env(:edenflowers, :mailerlite_req_options, []))
  end
end
