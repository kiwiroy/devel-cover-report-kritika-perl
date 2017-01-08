requires 'perl', '5.008001';

requires 'JSON';
requires 'HTTP::Tiny';
requires 'Devel::Cover';
requires 'Sereal::Encoder';
requires 'Sereal::Decoder';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

