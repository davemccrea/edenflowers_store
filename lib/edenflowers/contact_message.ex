defmodule Edenflowers.ContactMessage do
  @moduledoc """
  A message to Jennie from the contact form. Not an order, and nothing is
  stored: a valid message is queued as an Oban job that emails the sender a
  copy, bcc Jennie, so a failed send is retried rather than lost.
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
  end

  def submit(params, locale) do
    changeset = changeset(params)

    case apply_action(changeset, :insert) do
      # The honeypot field is hidden from people, so only bots fill it.
      # They're told it worked so they don't try again.
      {:ok, %{website: website}} when is_binary(website) ->
        :ok

      {:ok, message} ->
        args =
          message
          |> Map.take([:name, :email, :phone, :message])
          |> Map.put(:locale, locale)

        with {:ok, _job} <- args |> SendEmails.new() |> Oban.insert(), do: :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
