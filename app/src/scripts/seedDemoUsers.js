
const db = require("../db");
const bcrypt = require("bcrypt");

async function seedDemoUsers() {
    // Las cuentas predeterminadas solo pueden crearse en desarrollo.
    if (process.env.SEED_DEMO_USERS !== "true") {
        return;
    }

    const accounts = [
        {
            username: "Admin",
            email: "admin@admin.com",
            password: "admin123",
            role: "admin"
        },
        {
            username: "Usuario",
            email: "usuario@usuario.com",
            password: "usuario123",
            role: "user"
        }
    ];

    const [columns] = await db.query(
        `SELECT COLUMN_NAME
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = 'users'
           AND COLUMN_NAME = 'role'`
    );

    if (columns.length === 0) {
        try {
            await db.query(
                `ALTER TABLE users
                 ADD COLUMN role ENUM('user', 'admin')
                 NOT NULL DEFAULT 'user'`
            );
        } catch (error) {
            if (error.code !== "ER_DUP_FIELDNAME") {
                throw error;
            }
        }
    }

    for (const account of accounts) {
        const [existing] = await db.query(
            `SELECT user_id FROM users
             WHERE email = ? OR username = ?`,
            [account.email, account.username]
        );

        if (existing.length > 0) {
            console.log(
                `Cuenta de demostración ya existente: ${account.email}`
            );
            continue;
        }

        const passwordHash = await bcrypt.hash(account.password, 12);

        try {
            await db.query(
                `INSERT INTO users
                    (username, email, password_hash, role)
                 VALUES (?, ?, ?, ?)`,
                [
                    account.username,
                    account.email,
                    passwordHash,
                    account.role
                ]
            );
        } catch (error) {
            if (error.code !== "ER_DUP_ENTRY") {
                throw error;
            }

            const [createdByAnotherInstance] = await db.query(
                `SELECT user_id FROM users
                 WHERE email = ? AND username = ?`,
                [account.email, account.username]
            );

            if (createdByAnotherInstance.length === 0) {
                throw error;
            }

            console.log(
                `Cuenta de demostración ya existente: ${account.email}`
            );
            continue;
        }

        console.log(`Cuenta de demostración creada: ${account.email}`);
    }
}

module.exports = seedDemoUsers;
