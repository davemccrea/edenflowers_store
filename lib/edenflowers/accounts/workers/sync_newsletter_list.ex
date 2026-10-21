defmodule Edenflowers.Accounts.Workers.SyncNewsletterList do
  @moduledoc """
  Makes the Brevo newsletter list match the users who opted in: adds new
  subscribers and removes anyone who opted out.

  Unsubscribing from a Brevo campaign blocklists the contact straight away, so
  no more campaigns reach them; the next run opts the user out here and drops
  them from the list. A user who later opts in again isn't in the list, which shows their opt-in is newer than the
  unsubscribe, so adding them lifts the block. That only holds while Brevo's
  unsubscribe blocklists rather than just leaving the list; with a list-only
  unsubscribe page this would add people straight back.

  Customers who gave a phone number at checkout are kept as contacts too, off
  the list, so order texts can reach them. Their blocklist is left alone: they
  never opted in to campaigns.

  Each contact carries FIRSTNAME, LASTNAME, SMS (E.164, from their latest
  order), LANGUAGE (en-GB, sv-FI or fi), ORDER_COUNT, LAST_ORDER_DATE and
  TOTAL_SPENT, refreshed every run so changes reach Brevo. Apart from the
  built-in FIRSTNAME, LASTNAME and SMS these have to exist in Brevo: LANGUAGE
  as text, ORDER_COUNT and TOTAL_SPENT as number, LAST_ORDER_DATE as date.
  Brevo allows each SMS number on one contact only, so a number someone else
  already has (a shared household phone) is left off.

  The app owns this list, so contacts added to it by hand in Brevo are removed
  on the next run.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.PhoneNumber

  # Brevo's caps for one page of list contacts and one removal request.
  @page_size 500
  @remove_batch_size 150

  @impl true
  def perform(_job) do
    case Application.get_env(:edenflowers, :brevo_newsletter_list_id) do
      nil -> :ok
      list_id -> sync(list_id)
    end
  end

  defp sync(list_id) do
    {users, customers} =
      Accounts.list_brevo_contacts!(actor: system_actor())
      |> Enum.split_with(& &1.newsletter_opt_in)

    with {:ok, contacts} <- list_contacts(list_id, 0, []) do
      listed = MapSet.new(contacts, &normalize(&1["email"]))

      unsubscribed =
        for %{"emailBlacklisted" => true, "email" => email} <- contacts, into: MapSet.new(), do: normalize(email)

      {left, subscribers} = Enum.split_with(users, &(normalize(&1.email) in unsubscribed))
      Enum.each(left, &Accounts.update_newsletter_preference!(&1, false, &1.locale, actor: system_actor()))

      leaving = MapSet.difference(listed, MapSet.new(subscribers, &normalize(&1.email)))

      with :ok <- upsert_subscribers(list_id, subscribers),
           :ok <- upsert_customers(customers) do
        remove_contacts(list_id, leaving)
      end
    end
  end

  defp list_contacts(list_id, offset, acc) do
    case Req.get(client(), url: "/contacts/lists/#{list_id}/contacts", params: [limit: @page_size, offset: offset]) do
      {:ok, %Req.Response{status: 200, body: %{"contacts" => contacts}}} ->
        if length(contacts) == @page_size,
          do: list_contacts(list_id, offset + @page_size, acc ++ contacts),
          else: {:ok, acc ++ contacts}

      other ->
        brevo_error(other)
    end
  end

  # One request per contact, as Brevo's bulk import can't lift a blocklist.
  # ponytail: one POST per contact nightly, batch existing contacts through
  # /contacts/import if the list outgrows Brevo's rate limit.
  defp upsert_subscribers(list_id, users) do
    upsert_each(users, fn user ->
      %{
        email: normalize(user.email),
        attributes: attributes(user),
        listIds: [String.to_integer(list_id)],
        updateEnabled: true,
        emailBlacklisted: false
      }
    end)
  end

  defp upsert_customers(users) do
    upsert_each(users, fn user ->
      %{email: normalize(user.email), attributes: attributes(user), updateEnabled: true}
    end)
  end

  defp upsert_each(users, body_fun) do
    Enum.reduce_while(users, :ok, fn user, :ok ->
      case upsert_contact(body_fun.(user)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp upsert_contact(body) do
    case Req.post(client(), url: "/contacts", json: body) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: 400, body: %{"code" => "duplicate_parameter"}}}
      when is_map_key(body.attributes, :SMS) ->
        upsert_contact(%{body | attributes: Map.delete(body.attributes, :SMS)})

      other ->
        brevo_error(other)
    end
  end

  defp attributes(user) do
    %{
      FIRSTNAME: user.first_name,
      LASTNAME: user.last_name,
      SMS: e164(user.phone_number),
      LANGUAGE: user.locale,
      ORDER_COUNT: user.placed_order_count,
      LAST_ORDER_DATE: user.last_ordered_at && Date.to_iso8601(DateTime.to_date(user.last_ordered_at)),
      TOTAL_SPENT: Decimal.to_float(user.total_spent)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp e164(phone_number) do
    case PhoneNumber.format(phone_number, :e164) do
      {:ok, formatted} -> formatted
      :error -> nil
    end
  end

  defp remove_contacts(list_id, emails) do
    emails
    |> Enum.chunk_every(@remove_batch_size)
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      case Req.post(client(), url: "/contacts/lists/#{list_id}/contacts/remove", json: %{emails: batch}) do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> {:cont, :ok}
        other -> {:halt, brevo_error(other)}
      end
    end)
  end

  defp brevo_error({:ok, %Req.Response{status: status, body: body}}), do: {:error, {:brevo_http_error, status, body}}
  defp brevo_error({:error, reason}), do: {:error, {:brevo_request_failed, reason}}

  # Brevo stores addresses lowercased; the app keeps the case the customer typed.
  defp normalize(email), do: email |> to_string() |> String.downcase()

  defp client do
    Req.new(
      base_url: "https://api.brevo.com/v3",
      headers: [{"api-key", Application.fetch_env!(:edenflowers, :brevo_api_key)}]
    )
    |> Req.merge(Application.get_env(:edenflowers, :brevo_req_options, []))
  end
end
