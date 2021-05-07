FROM ruby:3.0-alpine

COPY . .

CMD ["./myhttpserver.rb"]
