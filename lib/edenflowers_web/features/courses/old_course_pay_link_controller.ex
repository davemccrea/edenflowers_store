defmodule EdenflowersWeb.Courses.OldCoursePayLinkController do
  @moduledoc """
  Sends course payment links emailed before they moved under `/pay` to their
  new path. Its route skips the browser pipeline, so maintenance mode never
  stops these links.
  """

  use EdenflowersWeb, :controller

  def show(conn, %{"token" => token}), do: redirect(conn, to: ~p"/pay/courses/#{token}")
end
