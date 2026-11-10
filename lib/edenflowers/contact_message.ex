defmodule Edenflowers.ContactMessage do
  @moduledoc """
  A message to Jennie from the contact form. Not an order, and nothing is
  stored: a valid message is queued as Oban jobs that email Jennie and acknowledge the sender, so a failed send is retried rather than lost.
  """

  import Ecto.Changeset

  alias Edenflowers.ContactMessage.SendEmails

  @types %{
    name: :string,
    email: :string,
    phone: :string,
    message: :string,
    website: :string
  }

  def changeset(params) do
    {%{}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:name, :email, :message])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/)
    |> validate_length(:message, max: 5000)
    |> validate_length(:name, max: 200)
    |> validate_length(:email, max: 200)
    |> validate_length(:phone, max: 200)
  end

  def submit(params, locale, client_ip) do
    changeset = changeset(params)

    case apply_action(changeset, :insert) do
      # The honeypot field is hidden from people, so only bots fill it.
      # They're told it worked so they don't try again.
      {:ok, %{website: website}} when is_binary(website) ->
        :ok

      {:ok, message} ->
        if rate_limited?(client_ip) do
          {:error, :rate_limited}
        else
          args =
            message
            |> Map.take([:name, :email, :phone, :message])
            |> Map.put(:locale, locale)

          acknowledgement = SendEmails.new(%{acknowledgement: true, email: message.email, locale: locale})
          Oban.insert_all([SendEmails.new(args), acknowledgement])
          :ok
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Each message also emails the typed address, so one visitor must not be able
  # to send it to many. No known address means no limit, as for sign-in.
  defp rate_limited?(nil), do: false

  defp rate_limited?(client_ip) do
    match?({:deny, _}, Edenflowers.RateLimiter.hit("contact:ip:#{client_ip}", :timer.hours(1), 5))
  end
end
