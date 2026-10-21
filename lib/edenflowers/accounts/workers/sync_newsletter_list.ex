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

  Each contact carries FIRSTNAME and LANGUAGE (en-GB, sv-FI or fi), refreshed
  every run so name changes reach Brevo. LANGUAGE has to exist as a text
  attribute in Brevo.

  The app owns this list, so contacts added to it by hand in Brevo are removed
  on the next run.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  import Edenflowers.Actors

  alias Edenflowers.Accounts

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
    users = Accounts.list_newsletter_subscribers!(actor: system_actor())

    with {:ok, contacts} <- list_contacts(list_id, 0, []) do
      listed = MapSet.new(contacts, &normalize(&1["email"]))

      unsubscribed =
        for %{"emailBlacklisted" => true, "email" => email} <- contacts, into: MapSet.new(), do: normalize(email)

      {left, subscribers} = Enum.split_with(users, &(normalize(&1.email) in unsubscribed))
      Enum.each(left, &Accounts.update_newsletter_preference!(&1, false, &1.locale, actor: system_actor()))

      leaving = MapSet.difference(listed, MapSet.new(subscribers, &normalize(&1.email)))

      with :ok <- upsert_contacts(list_id, subscribers) do
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
  # ponytail: one POST per subscriber nightly, batch existing contacts through
  # /contacts/import if the list outgrows Brevo's rate limit.
  defp upsert_contacts(list_id, users) do
    Enum.reduce_while(users, :ok, fn user, :ok ->
      body = %{
        email: normalize(user.email),
        attributes: attributes(user),
        listIds: [String.to_integer(list_id)],
        updateEnabled: true,
        emailBlacklisted: false
      }

      case Req.post(client(), url: "/contacts", json: body) do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> {:cont, :ok}
        other -> {:halt, brevo_error(other)}
      end
    end)
  end

  defp attributes(user) do
    %{FIRSTNAME: user.first_name, LANGUAGE: user.locale}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
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
