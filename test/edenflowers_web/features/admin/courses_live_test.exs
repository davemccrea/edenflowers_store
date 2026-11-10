defmodule EdenflowersWeb.Admin.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  setup :log_in_admin

  test "keeps drafts visible to the admin and marks their status", %{conn: conn} do
    course = generate(course(draft: true))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    render_async(view, 500)

    assert has_element?(view, ~s|tbody a[href="/admin/courses/#{course.id}"]|)
    assert has_element?(view, "tbody tr", "Draft")
  end

  test "lists a course with its booked seats and links to its page", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))
    generate(course_registration(course_id: course.id, status: :confirmed, seats: 3))
    generate(course_registration(course_id: course.id, status: :pending))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    render_async(view, 500)

    assert has_element?(view, "tbody tr", "3 / 10")
    assert has_element?(view, ~s|tbody a[href="/admin/courses/#{course.id}"]|, "Autumn wreaths")
    assert has_element?(view, "tbody tr", "Published")
  end

  test "refreshes when a course changes elsewhere", %{conn: conn, admin: admin} do
    course = generate(course(name: "Autumn wreaths"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    render_async(view, 500)

    assert has_element?(view, "tbody a", "Autumn wreaths")

    {:ok, _course} = Ash.update(course, %{name: "Winter wreaths"}, actor: admin)
    Process.sleep(200)

    assert has_element?(view, "tbody a", "Winter wreaths")
  end

  test "filters draft and published courses while keeping the period filter", %{conn: conn} do
    generate(course(name: "Draft wreaths", draft: true))
    generate(course(name: "Published wreaths", draft: false))
    past_course("Past wreaths")

    for {draft, shown, hidden} <- [
          {"true", "Draft wreaths", "Published wreaths"},
          {"false", "Published wreaths", "Draft wreaths"}
        ] do
      {:ok, view, _html} = live(conn, ~p"/admin/courses?#{[draft: draft, period: "current"]}")
      render_async(view, 500)

      assert has_element?(view, "tbody tr", shown)
      refute has_element?(view, "tbody tr", hidden)
      refute has_element?(view, "tbody tr", "Past wreaths")
    end
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

  defp past_course(name),
    do: generate(course(name: name)) |> Ash.Seed.update!(%{date: Date.add(Edenflowers.ShopTime.today(), -7)})
end
