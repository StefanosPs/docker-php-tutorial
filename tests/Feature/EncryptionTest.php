<?php

namespace Tests\Feature;

use PHPUnit\Framework\TestCase;

class EncryptionTest extends TestCase
{
    public function test_ensure_that_the_secret_passwords_file_was_decrypted(): void
    {
        $pathToSecretFile = __DIR__."/../../passwords.txt";

        $this->assertFileExists($pathToSecretFile);
        
        $expected = "my_secret_passwor\n";
        $actual   = file_get_contents($pathToSecretFile);

        $this->assertEquals($expected, $actual);
    }
}
