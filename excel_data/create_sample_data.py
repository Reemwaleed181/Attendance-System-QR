import pandas as pd
import os

# Create sample classes data
classes_data = {
    'name': [
        'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5',
        'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10'
    ],
    'teacher': [
        'Ms. Sarah Johnson', 'Mr. Ahmed Hassan', 'Mrs. Fatima Ali', 'Mr. Omar Khalil', 'Ms. Layla Mahmoud',
        'Mr. Youssef Ibrahim', 'Mrs. Nour Ahmed', 'Mr. Khalid Omar', 'Ms. Mariam Hassan', 'Mr. Ali Ibrahim'
    ],
    'capacity': [25, 25, 25, 25, 25, 25, 25, 25, 25, 25]
}

# Create sample students data
students_data = {
    'name': [
        'Ahmed Ali', 'Aliaa Ali', 'Ibrahim Ali', 'Reem Omaran', 'Amina Omaran', 'Mahmoud Omaran',
        'Ali Mohammed', 'Aisha Mohammed', 'Nada Mohammed', 'Khadeja Khalil', 'Hala Khalil', 'Sara Khalil',
        'Omran Omar', 'Layla Omar', 'Zainab Omar', 'Nada Omar', 'Tariq Omar',
        'Yaser Youssef', 'Tariq Youssef', 'Zainab Youssef', 'Noura Adam', 'Khalid Adam',
        'Aser Khalid', 'Mahmoud Khalid', 'Malk Ibrahim', 'Sara Ibrahim',
        'Aisha Ibrahim', 'Hassan Ibrahim', 'Hala Ibrahim', 'Khalil Ibrahim', 'Tala Ibrahim'
    ],
    'class': [
        'Class 1', 'Class 2', 'Class 3', 'Class 1', 'Class 2', 'Class 3',
        'Class 4', 'Class 5', 'Class 6', 'Class 4', 'Class 5', 'Class 6',
        'Class 7', 'Class 8', 'Class 9', 'Class 7', 'Class 8',
        'Class 10', 'Class 1', 'Class 2', 'Class 3', 'Class 4',
        'Class 5', 'Class 6', 'Class 7', 'Class 8',
        'Class 9', 'Class 10', 'Class 1', 'Class 2', 'Class 3'
    ]
}

# Create sample parents data
parents_data = {
    'name': [
        'Ali Hassan', 'Fatima Omar', 'Mohammed Ibrahim', 'Aisha Khalid', 'Omar Ahmed',
        'Youssef Hassan', 'Nouran Ali', 'Khalid Omar', 'Mariam Ibrahim', 'Ahmed Ibrahim'
    ],
    'email': [
        'ali.hassan@email.com', 'fatima.omar@email.com', 'mohammed.ibrahim@email.com',
        'aisha.khaled@email.com', 'omar.ahmed@email.com', 'youssef.hassan@email.com',
        'nouran.ali@email.com', 'khalid.omar@email.com', 'mariam.ibrahim@email.com',
        'ahmed.ibrahim@email.com'
    ],
    'phone': [
        '+1234567890', '+1234567891', '+1234567892', '+1234567893', '+1234567894',
        '+1234567896', '+1234567897', '+1234567898', '+1234567899', '+1234567900'
    ],
    'children': [
        'Ahmed Ali;Aliaa Ali;Ibrahim Ali', 'Reem Omaran;Amina Omaran;Mahmoud Omaran', 
        'Ali Mohammed;Aisha Mohammed;Nada Mohammed', 'Khadeja Khalil;Hala Khalil;Sara Khalil', 
        'Omran Omar;Layla Omar;Zainab Omar;Nada Omar;Tariq Omar',
        'Yaser Youssef;Tariq Youssef;Zainab Youssef', 'Noura Adam;Khalid Adam', 
        'Aser Khalid;Mahmoud Khalid', 'Malk Ibrahim;Sara Ibrahim',
        'Aisha Ibrahim;Hassan Ibrahim;Hala Ibrahim;Khalil Ibrahim;Tala Ibrahim'
    ]
}

# Create DataFrames and save to Excel
classes_df = pd.DataFrame(classes_data)
students_df = pd.DataFrame(students_data)
parents_df = pd.DataFrame(parents_data)

# Save to Excel files
classes_df.to_excel('classes.xlsx', index=False)
students_df.to_excel('students.xlsx', index=False)
parents_df.to_excel('parents.xlsx', index=False)

print("Sample Excel files created successfully!")
print(f"Classes: {len(classes_df)} records")
print(f"Students: {len(students_df)} records")
print(f"Parents: {len(parents_df)} records")
