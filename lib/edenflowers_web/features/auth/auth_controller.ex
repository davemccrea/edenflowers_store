defmodule EdenflowersWeb.Auth.AuthController do
  @moduledoc """
  Handles authentication callbacks and redirects visitors back to their intended page.
  """

  use EdenflowersWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~q"/#{language}"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:success, ~t"You are now signed in")
    |> redirect(to: return_to)
  end

  def failure(conn, activity, _reason) do
    message =
      case activity do
        {:otp, :sign_in} -> ~t"That code didn't work. Check it and try again, or send a new code."
        _ -> ~t"We couldn't sign you in. Please try again."
      end

    conn
    |> put_otp_email(activity)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  # Lets OtpSignInLive reopen the code step for the same email after a wrong code.
  defp put_otp_email(conn, {:otp, :sign_in}) do
    case conn.params do
      %{"user" => %{"email" => email}} when is_binary(email) -> put_flash(conn, :otp_email, email)
      _ -> conn
    end
  end

  defp put_otp_email(conn, _activity), do: conn

  # The account pages' "Sign out of all devices": revokes every token the
  # user holds, so their other browsers and installed apps are signed out too.
  def sign_out(%{assigns: %{current_user: %{} = user}} = conn, %{"everywhere" => "true"}) do
    :ok = Edenflowers.Accounts.log_out_everywhere(user, actor: user)

    conn
    |> clear_session(:edenflowers)
    |> put_flash(:success, ~t"You are now signed out on all your devices")
    |> redirect(to: ~q"/#{language}")
  end

  def sign_out(conn, _params) do
    conn
    |> clear_session(:edenflowers)
    |> put_flash(:success, ~t"You are now signed out")
    |> redirect(to: ~q"/#{language}")
  end
end
