defmodule Plug.Conn.CookiesTest do
  use ExUnit.Case, async: true

  import Plug.Conn.Cookies
  doctest Plug.Conn.Cookies

  test "decode cookies" do
    assert decode("key1=value1, key2=value2") == %{"key1" => "value1, key2=value2"}
    assert decode("key1=value1; key2=value2") == %{"key1" => "value1", "key2" => "value2"}

    assert decode("$key1=value1, key2=value2; $key3=value3") == %{
             "$key1" => "value1, key2=value2",
             "$key3" => "value3"
           }

    assert decode("key space=value, key=value space") == %{}
    assert decode("  key1=value1 , key2=value2  ") == %{"key1" => "value1 , key2=value2"}
    assert decode("") == %{}
    assert decode("=") == %{}
    assert decode("=;") == %{}
    assert decode("key, =, value") == %{}
    assert decode("key=") == %{"key" => ""}
    assert decode("key1=;;key2=") == %{"key1" => "", "key2" => ""}

    for whitespace <- ["\s", "\t", "\r", "\n", "\v", "\f"] do
      assert decode("#{whitespace}=value") == %{}
      assert decode("#{whitespace}=#{whitespace}") == %{}

      if whitespace == "\s" do
        assert decode("key=#{whitespace}") == %{"key" => ""}
      else
        assert decode("key=#{whitespace}") == %{}
      end
    end
  end

  test "decodes encoded cookie" do
    start = {{2012, 9, 29}, {15, 32, 10}}
    cookie = encode("foo", %{value: "bar", max_age: 60, universal_time: start})

    assert decode(cookie) == %{
             "foo" => "bar",
             "expires" => "Sat, 29 Sep 2012 15:33:10 GMT",
             "max-age" => "60",
             "path" => "/"
           }
  end

  test "encodes the cookie" do
    assert encode("foo", %{value: "bar"}) == "foo=bar; path=/; HttpOnly"
    assert encode("foo", %{}) == "foo=; path=/; HttpOnly"
    assert encode("foo") == "foo=; path=/; HttpOnly"
  end

  test "encodes with :path option" do
    assert encode("foo", %{value: "bar", path: "/baz"}) == "foo=bar; path=/baz; HttpOnly"
  end

  test "encodes with :domain option" do
    assert encode("foo", %{value: "bar", domain: "google.com"}) ==
             "foo=bar; path=/; domain=google.com; HttpOnly"
  end

  test "encodes with :secure option" do
    assert encode("foo", %{value: "bar", secure: true}) == "foo=bar; path=/; secure; HttpOnly"
  end

  test "encodes without :same_site option if not set" do
    assert encode("foo", %{value: "bar"}) == "foo=bar; path=/; HttpOnly"
  end

  test "encodes with :same_site option :lax" do
    assert encode("foo", %{value: "bar", same_site: "Lax"}) ==
             "foo=bar; path=/; HttpOnly; SameSite=Lax"
  end

  test "encodes with :same_site option :strict" do
    assert encode("foo", %{value: "bar", same_site: "Strict"}) ==
             "foo=bar; path=/; HttpOnly; SameSite=Strict"
  end

  test "encodes with :same_site option :none" do
    assert encode("foo", %{value: "bar", same_site: "None"}) ==
             "foo=bar; path=/; HttpOnly; SameSite=None"
  end

  test "encodes with :http_only option, which defaults to true" do
    assert encode("foo", %{value: "bar", http_only: false}) == "foo=bar; path=/"
  end

  test "encodes with :max_age" do
    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 1, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Sat, 07 Jan 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 2, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Tue, 07 Feb 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 3, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Wed, 07 Mar 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 4, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Sat, 07 Apr 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 5, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Mon, 07 May 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 6, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Thu, 07 Jun 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 7, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Sat, 07 Jul 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 8, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Tue, 07 Aug 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 9, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Fri, 07 Sep 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 10, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Sun, 07 Oct 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 11, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Wed, 07 Nov 2012 15:33:10 GMT; max-age=60; HttpOnly"

    assert encode("foo", %{
             value: "bar",
             max_age: 60,
             universal_time: {{2012, 12, 7}, {15, 32, 10}}
           }) ==
             "foo=bar; path=/; expires=Fri, 07 Dec 2012 15:33:10 GMT; max-age=60; HttpOnly"
  end

  test "encodes with :extra option" do
    assert encode("foo", %{value: "bar", extra: "SameSite=Lax"}) ==
             "foo=bar; path=/; HttpOnly; SameSite=Lax"
  end
end
