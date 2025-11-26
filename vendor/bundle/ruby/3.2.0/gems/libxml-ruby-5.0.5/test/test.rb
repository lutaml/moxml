begin
  File.open("/does/not/exist")
rescue => e
  puts e
end
