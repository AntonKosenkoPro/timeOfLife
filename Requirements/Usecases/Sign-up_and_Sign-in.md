## User registration and sign-in via email address
    1. User opens the app and sees the start screen
    2. User types their email address into the email field
    3. User taps the Continue button
       1. If the email is not valid, the user gets a validation error with an error message
       2. Otherwise, the user navigates to the OTP page
    4. On the OTP page, the user enters the OTP code
       1. If the code is not valid, the user gets a validation error with an error message
       2. If the user realises the email is incorrect, they navigate back to correct it
          1. User taps the back button and returns to the start page with the email field pre-filled
       3. If the user cannot receive the code, they will be able to resend it
          1. After waiting for 30 seconds, the Resend code button becomes enabled
          2. When the code is resent, the user gets an appropriate feedback message
       4. If the code is valid, the user navigates to the main product page 
