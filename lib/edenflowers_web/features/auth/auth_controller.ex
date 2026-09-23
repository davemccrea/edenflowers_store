defmodule EdenflowersWeb.Auth.AuthController do
  use EdenflowersWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> ~t"Your email address has now been confirmed"
        {:password, :reset} -> ~t"Your password has successfully been reset"
        _ -> ~t"You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          ~t"You have already signed in another way, but have not confirmed your account. You can confirm your account using the link we sent to you, or by resetting your password."

        {{:google, _}, _} ->
          ~t"We couldn't sign you in with Google. Please try again or use a sign-in code."

        {{:otp, :sign_in}, _} ->
          ~t"That code didn't work. Check it and try again, or send a new code."

        _ ->
          ~t"We couldn't sign you in. Please try again."
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

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:edenflowers)
    |> put_flash(:info, ~t"You are now signed out")
    |> redirect(to: return_to)
  end
end
