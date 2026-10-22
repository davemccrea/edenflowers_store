defmodule EdenflowersWeb.Admin.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "lists a course with its booked seats and links to its page", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))
    generate(course_registration(course_id: course.id, status: :confirmed, seats: 3))
    generate(course_registration(course_id: course.id, status: :pending))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    render_async(view, 500)

    assert has_element?(view, "tbody tr", "3 / 10")
    assert has_element?(view, ~s|tbody a[href="/admin/courses/#{course.id}"]|, "Autumn wreaths")
  end

  test "opens on current courses: upcoming, and past ones until their bookings are settled", %{conn: conn} do
    generate(course(name: "Autumn wreaths"))
    owing = past_course("Spring posies")
    generate(course_registration(course_id: owing.id, status: :confirmed))
    past_course("Winter garlands")

    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    render_async(view, 500)

    assert has_element?(view, "tbody tr", "Autumn wreaths")
    assert has_element?(view, "tbody tr", "Past")
    assert has_element?(view, "tbody tr", "To settle")
    refute has_element?(view, "tbody tr", "Winter garlands")

    {:ok, view, _html} = live(conn, ~p"/admin/courses?period=past")
    render_async(view, 500)

    assert has_element?(view, "tbody tr", "Winter garlands")
    refute has_element?(view, "tbody tr", "Autumn wreaths")
  end

  test "View in store opens the public courses listing in a new tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    assert has_element?(view, ~s|a[href="/en/courses"][target="_blank"]|, "View in store")
  end

  defp past_course(name),
    do: generate(course(name: name)) |> Ash.Seed.update!(%{date: Date.add(Edenflowers.ShopTime.today(), -7)})
end
